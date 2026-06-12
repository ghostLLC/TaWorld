## TaWorld AI 主动消息 & 动作执行 — 技术调研报告

> 调研时间：2026-06-12
> 目标：让 AI 能主动给用户发消息、能执行实际动作（设提醒、发通知等）

---

### 一、现有架构基础

APP 已具备以下可直接复用的基础设施：

| 模块 | 位置 | 能力 |
|------|------|------|
| WorkManager 后台任务 | `background_tasks.dart` | 天气轮询（2h）+ 通知续期（12h），在独立 Isolate 运行 |
| flutter_local_notifications | `notification_service.dart` | 即时通知 + zonedSchedule 精确定时通知 |
| DeepSeek API | `ai_service.dart` | 流式聊天 + 结构化建议生成 + 10 条历史上下文 |
| CareSuggestionService | `care_suggestion_service.dart` | 上下文感知建议（时间+天气+关系类型），AI 优先、本地模板兜底 |
| ReminderScheduler | `reminder_scheduler.dart` | 7 天滚动排程 + 12h 自动续期 + 预创建日志 |
| SQLite 数据库 | `database_helper.dart` | 7 张表（users, partners, reminder_configs, reminder_logs, achievements, user_achievements, chat_history） |
| SharedPreferences | 全局 | API Key 管理 + 通知去重标记 |

---

### 二、DeepSeek Function Calling 能力

#### 2.1 API 格式

DeepSeek 兼容 OpenAI 的 tool calling 协议。请求体新增 `tools` 数组：

```json
{
  "model": "deepseek-chat",
  "messages": [
    {"role": "system", "content": "你是关怀助手，可以帮用户设置提醒..."},
    {"role": "user", "content": "帮我设一个每天晚上10点提醒小明睡觉的提醒"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "create_reminder",
        "description": "为关心的人创建一条定时提醒",
        "parameters": {
          "type": "object",
          "properties": {
            "partner_name": {"type": "string", "description": "关心的人的名字"},
            "category": {"type": "string", "enum": ["sleep", "meal", "weather", "custom"]},
            "time": {"type": "string", "description": "提醒时间，格式 HH:mm"},
            "message": {"type": "string", "description": "提醒消息内容"}
          },
          "required": ["partner_name", "category", "time"]
        }
      }
    }
  ]
}
```

#### 2.2 响应格式

当模型决定调用工具时，response 的 `choices[0].message` 包含 `tool_calls`：

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {
          "name": "create_reminder",
          "arguments": "{\"partner_name\":\"小明\",\"category\":\"sleep\",\"time\":\"22:00\"}"
        }
      }]
    }
  }]
}
```

#### 2.3 回传结果

执行完工具后，将结果作为 `role: "tool"` 消息发回：

```json
{
  "messages": [
    // ... 之前的消息 ...
    {"role": "tool", "tool_call_id": "call_abc123", "content": "已成功创建提醒：每天晚上22:00提醒小明睡觉"}
  ]
}
```

模型会根据工具结果生成最终回复。

#### 2.4 支持的模型

| 模型 | Function Calling | 备注 |
|------|-----------------|------|
| deepseek-chat (V3.2+) | 支持（thinking 模式） | APP 当前使用的模型 |
| deepseek-reasoner | 不支持 | 推理模型，不适合对话场景 |

#### 2.5 限制

- 建议 tools 数量不超过 10 个（过多会影响质量）
- 每次对话最多 10 轮 tool call（防止无限循环）
- `strict` 模式（beta）可强制 JSON Schema 合规，但需要 `/beta` 端点
- 流式输出与 tool calling 可以共存，但 tool call 参数会在一个完整的 `tool_calls` chunk 中返回

---

### 三、功能一：AI 主动发消息

#### 3.1 核心思路

> **定时器 + 上下文收集 + AI 评估 + 通知/插入对话**

不是让 AI 凭空主动说话，而是：定时任务收集上下文 → 调用 AI 判断"现在是否值得主动联系用户" → 如果值得，生成消息 → 通过通知或插入对话的方式触达用户。

#### 3.2 触发时机（定时器 + 钩子）

**方案 A：WorkManager 后台定时评估（推荐）**

```
每 2 小时触发一次 → 收集所有关心的人的上下文
→ 调用 AI 评估是否需要主动联系
→ 如果需要：生成消息 + 推送通知
→ 如果不需要：静默跳过
```

**方案 B：事件钩子触发**

在以下事件中自动触发 AI 评估：

| 事件 | 钩子位置 | AI 判断内容 |
|------|---------|------------|
| 天气突变 | `WeatherService.checkConditions()` 返回 shouldRemind=true 时 | 生成更有温度的提醒文案（替代硬编码文本） |
| 连续 N 天未关心某人 | `_loadData()` 加载 partner 数据时计算 `last_contacted_at` | "你已经 3 天没关心小明了，要不要发条消息？" |
| 对方生日/纪念日临近 | 新增 `partner_events` 表，WorkManager 每日检查 | "小明的生日后天就到了，要不要准备点什么？" |
| 用户打开 APP | `_init()` 方法中 | 根据最近上下文生成个性化问候（替代当前的固定模板） |

#### 3.3 实现架构

```
┌─────────────────────────────────────────────────┐
│  BackgroundTaskService (WorkManager)            │
│  ├─ _taskWeatherCheck (现有，2h)                │
│  ├─ _taskNotificationRenew (现有，12h)          │
│  └─ _taskAiProactiveCheck (新增，2h)            │
│     │                                           │
│     ▼                                           │
│  AiProactiveService.evaluate()                  │
│     │  1. 读取所有 partners                      │
│     │  2. 收集每人上下文：                        │
│     │     - 当前天气 (WeatherService)             │
│     │     - 距离上次联系的天数                     │
│     │     - 已配置的提醒                          │
│     │     - 当前时间/时段                         │
│     │  3. 调用 AI（结构化 prompt）                │
│     │     → 返回 JSON:                           │
│     │       { should_notify: bool,              │
│     │         category: "weather"|"miss"|"event",│
│     │         message: "消息内容",                │
│     │         confidence: 0.0~1.0 }              │
│     │  4. 去重检查（SharedPreferences）            │
│     │  5. 发送通知 or 插入待发消息队列              │
│     ▼                                           │
│  NotificationService.show()                     │
│  or DB insert → ai_pending_messages             │
└─────────────────────────────────────────────────┘
```

#### 3.4 新增数据结构

```sql
-- AI 主动消息队列（后台评估后写入，前台打开时消费）
CREATE TABLE ai_pending_messages (
  id TEXT PRIMARY KEY,
  partner_id TEXT REFERENCES partners(id),
  category TEXT NOT NULL,        -- weather/miss/event/greeting
  message TEXT NOT NULL,         -- AI 生成的消息
  confidence REAL DEFAULT 0.5,   -- AI 评估置信度
  status TEXT DEFAULT 'pending', -- pending/shown/dismissed
  created_at TEXT NOT NULL,
  shown_at TEXT
);
```

#### 3.5 用户体验流程

```
后台（用户无感知）：
  每2小时 → 收集上下文 → AI评估 → 置信度>0.7 → 写入 pending_messages + 推送通知

前台（用户打开APP）：
  _init() → 检查 ai_pending_messages 中 status='pending'
  → 插入聊天对话中（作为 AI 的主动消息）
  → 标记 status='shown'
  → 用户可以直接回复（进入正常对话流）
```

#### 3.6 防骚扰机制

- **全局冷却期**：两次主动消息之间至少间隔 4 小时
- **置信度阈值**：AI 返回 confidence < 0.7 时不发送
- **用户可关闭**：设置页增加"AI 主动关怀"开关（存入 SharedPreferences）
- **夜间静默**：22:00~08:00 不发送主动通知（除非是紧急天气预警）
- **每日上限**：同一天最多 2 条主动消息

---

### 四、功能二：AI 执行实际动作（Function Calling）

#### 4.1 核心思路

> **聊天中注入 tools 定义 → AI 返回 tool_calls → 本地执行 → 回传结果 → AI 生成确认回复**

用户在聊天中说"帮我设个提醒"时，AI 不是只能生成文字建议，而是真的可以调用本地服务来创建提醒。

#### 4.2 可定义的工具

根据 APP 现有能力，可以定义以下 5~6 个工具：

| 工具名 | 用途 | 对应服务 |
|--------|------|---------|
| `create_reminder` | 为某人创建定时提醒 | `LocalReminderService.create()` |
| `get_partner_weather` | 查询某人的当前天气 | `WeatherService.getCurrentWeather()` |
| `get_partner_info` | 获取某人的基本信息 | `PartnerService.getById()` |
| `send_care_message` | 生成一条关怀消息草稿 | `CareSuggestionService.generate()` |
| `get_reminder_stats` | 获取提醒统计数据 | `LocalReminderService.getStats()` |
| `set_partner_note` | 为某人添加备注 | `PartnerService.update()` |

#### 4.3 对话流程

```
用户: "帮我每天晚上10点提醒小明早点睡"

→ 第1轮 API 调用（带 tools）
← AI 返回 tool_calls: create_reminder(partner="小明", category="sleep", time="22:00")

→ 本地执行: LocalReminderService.createReminder(...)
   → 创建 reminder_config 记录
   → 调用 ReminderScheduler.scheduleAll()
   → 返回 "成功"

→ 第2轮 API 调用（带上 tool result）
← AI 生成自然语言回复: "搞定了|||每天晚上10点我会提醒你让小明早点睡|||别自己先睡着了哈哈"
```

#### 4.4 实现架构

```dart
// ai_service.dart 新增方法

/// 带工具调用的流式对话
static Future<String> chatWithTools(
  String userMessage, {
  required void Function(String) onToken,
  required Future<String> Function(String name, Map<String, dynamic> args) onToolCall,
}) async {
  // 1. 构建消息列表（system + history + user）
  // 2. 注入 tools 定义
  // 3. 调用 API
  // 4. 检查 response:
  //    a. 如果有 tool_calls → 执行 onToolCall → 将结果作为 tool message 再次调用 API
  //    b. 如果有 content → 直接流式输出
  // 5. 保存完整对话到 DB
}
```

#### 4.5 AI 主屏集成

```dart
// ai_home_screen.dart 修改 _sendMessage

Future<void> _sendMessage() async {
  // ... 现有的流式发送逻辑 ...
  
  await AiService.chatWithTools(text,
    onToken: (accumulated) {
      // 实时更新气泡（现有逻辑）
    },
    onToolCall: (name, args) async {
      // 显示"正在执行动作"的指示
      setState(() => _executingTool = name);
      
      final result = await _executeTool(name, args);
      
      setState(() => _executingTool = null);
      return result;
    },
  );
}

/// 本地工具执行器
Future<String> _executeTool(String name, Map<String, dynamic> args) async {
  switch (name) {
    case 'create_reminder':
      return await _toolCreateReminder(args);
    case 'get_partner_weather':
      return await _toolGetWeather(args);
    // ... 其他工具
  }
}
```

#### 4.6 工具执行器实现

```dart
Future<String> _toolCreateReminder(Map<String, dynamic> args) async {
  // 1. 按名字查找 partner
  final partners = await PartnerService.getAll();
  final partner = partners.firstWhere(
    (p) => p.nickname == args['partner_name'],
    orElse: () => throw Exception('未找到 ${args['partner_name']}'),
  );

  // 2. 创建 reminder_config
  final config = ReminderConfig(
    id: uuid.v4(),
    partnerId: partner.id,
    category: args['category'] ?? 'custom',
    enabled: true,
    config: {
      'time': args['time'] ?? '22:00',
      'advance_minutes': 30,
      'message': args['message'],
    },
  );
  await LocalReminderService.createConfig(config);

  // 3. 重新排程
  await ReminderScheduler.scheduleAll();

  return '成功创建提醒：每天${args['time']}提醒${args['partner_name']}${args['category'] == 'sleep' ? '早点休息' : ''}';
}
```

#### 4.7 流式 + 工具调用的兼容

DeepSeek 的流式输出与工具调用可以共存：
- 如果 AI 决定调用工具：`delta` 中会包含 `tool_calls` 字段
- 如果 AI 直接回复文本：正常流式输出

实现方式：解析每个 SSE chunk 时，同时检查 `delta.content` 和 `delta.tool_calls`。

---

### 五、两个功能的协同

主动消息 + 动作执行可以协同工作：

```
后台定时任务（主动消息评估）：
  AI 评估结果: { should_notify: true, suggested_action: "create_reminder", ... }
  → 自动执行动作（不需要用户确认）
  → 通知用户："我帮你给小明设了个睡觉提醒，每天晚上10点"

前台聊天（动作执行）：
  用户: "帮我关心一下小明"
  → AI 调用 get_partner_weather("小明") 获取天气
  → AI 调用 send_care_message("小明") 生成消息草稿
  → AI 回复: "小明那边今天降温了|||你可以跟他说注意保暖|||我帮你拟了条消息你看看"
  → 展示消息草稿卡片，用户确认后复制/分享
```

---

### 六、实施优先级建议

| 优先级 | 功能 | 工作量 | 用户感知 |
|--------|------|--------|---------|
| P0 | Function Calling 对话（前台） | 中 | 高 — AI 从"只能说"变成"能做事" |
| P1 | AI 主动问候（用户打开 APP 时） | 小 | 中 — 替代现有固定模板 |
| P1 | 天气突变时 AI 生成个性化文案 | 小 | 中 — 替代硬编码通知文本 |
| P2 | WorkManager 后台定时评估 | 大 | 高 — 真正的主动关怀 |
| P2 | 事件钩子（未联系天数、生日等） | 中 | 高 — 有温度的触发 |
| P3 | 通知内直接操作（发送/忽略按钮） | 中 | 中 — 减少操作步骤 |

**建议第一步**：先实现 Function Calling（P0），让 AI 在对话中能真正创建提醒和查天气。这是投入产出比最高的改动，只需要修改 `ai_service.dart` 和 `ai_home_screen.dart` 两个文件。

---

### 七、涉及的文件变更清单

| 文件 | 变更类型 | 内容 |
|------|---------|------|
| `ai_service.dart` | 修改 | 新增 `chatWithTools()` 方法 + tools 定义 |
| `ai_home_screen.dart` | 修改 | `_sendMessage` 改用 chatWithTools + 工具执行器 |
| `background_tasks.dart` | 修改 | 新增 `_taskAiProactiveCheck` |
| `notification_service.dart` | 修改 | 新增 AI 主动消息通知渠道 |
| `database_helper.dart` | 修改 | 新增 `ai_pending_messages` 表 |
| `ai_proactive_service.dart` | 新增 | AI 主动评估服务 |
| `local_reminder_service.dart` | 修改 | 新增 AI 工具调用入口 |
