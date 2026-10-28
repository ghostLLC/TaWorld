## TaWorld AI 记忆系统升级方案

### Wiki + RAG 混合记忆架构 — 调研结论与实施路线

---

### 一、调研核心结论

经过对 Mem0、Zep/Graphiti、Letta/MemGPT、ChatGPT Memory、LangMem 等主流 AI 记忆系统的深度调研，行业在 2025-2026 年已收敛到一个两层架构共识：

**Wiki 层（语义记忆）** 类似人脑的"知识记忆"，存储经过提炼的结构化事实——用户姓名、关心的人、偏好、重要日期等。这些事实始终注入到每次对话的上下文中，成本低、效果显著。

**RAG 层（情景记忆）** 类似人脑的"经历记忆"，通过向量检索从历史对话中召回特定片段。当用户说"上次我心情不好的时候我们聊了什么"，系统能精确定位到那段对话。

两者缺一不可：只有 Wiki 无法回忆具体经历，只有 RAG 则每次对话都从零开始、且 token 消耗巨大。

ChatGPT 在 2025 年引入的"Dreaming"（做梦式记忆整合）是一个重要突破——在空闲时段自动合并重复记忆、消解矛盾、将频繁出现的情景记忆提升为 Wiki 事实。实测数据显示事实召回准确率提升到 82.8%，计算成本降低约 80%。这个思路非常适合 TaWorld 的后台任务架构。

---

### 二、TaWorld 现状分析

#### 2.1 已有的数据资产

TaWorld 其实已经拥有丰富的结构化数据，只是这些数据与 AI 对话系统之间存在严重的"信息孤岛"：

| 数据源 | 内容 | 当前是否用于 AI |
|--------|------|----------------|
| `users` 表 | 用户昵称、头像 | 否 — AI 不知道用户叫什么 |
| `partners` 表 | 关心的人的姓名、关系、城市、备注 | 仅通过工具调用获取 |
| `reminder_configs` 表 | 提醒配置（睡觉/吃饭/天气） | 仅通过工具调用获取 |
| `reminder_logs` 表 | 提醒发送历史 | 完全未使用 |
| `achievements` + `user_achievements` | 成就进度 | 完全未使用 |
| `chat_history` 表 | 对话历史 | 仅最近 10 条直接拼接 |
| `ai_pending_messages` 表 | AI 主动消息 | 消费后即丢弃 |

#### 2.2 当前 AI 上下文的致命缺陷

现在的系统提示词 `_chatSystemPrompt` 只包含回复格式指令，**零用户数据**。这意味着每次对话：

- AI 不知道用户叫什么名字
- AI 不知道用户关心哪些人，除非主动调用工具
- AI 不知道现在是什么时间段（早上/晚上）
- AI 不知道用户之前设过什么提醒
- AI 不记得超过 10 条消息之前的任何对话
- 用户在聊天中提到的信息（比如"我妈下周生日"）说完就丢

而讽刺的是，`AiProactiveService.evaluate()` 在后台评估时构建的上下文（包含所有 partner 信息、天气、提醒配置）远比聊天 AI 拥有的上下文丰富——但这两个系统完全断裂。

#### 2.3 关键差距总结

按优先级排序：

**P0（必须立即解决）：** 用户身份不在系统提示中；关心的人列表不在系统提示中；没有时间感知。

**P1（高优先级）：** 活跃提醒不在上下文中；partner 备注未暴露；没有对话摘要机制。

**P2（中优先级）：** 成就进度对 AI 不可见；主动服务上下文不与聊天共享；无对话数据回流。

**P3（长期价值）：** 无从对话中提取事实和偏好的机制；无记忆衰减和整合。

---

### 三、推荐架构方案

结合 TaWorld 的特点——纯本地 SQLite、无服务器、Flutter 移动端、DeepSeek V4 API——推荐以下分阶段实施方案：

#### 3.1 整体架构

```
┌──────────────────────────────────────────────────────────┐
│                    TaWorld 记忆系统                        │
│                                                          │
│  ┌──────────────────┐    ┌─────────────────────────────┐ │
│  │  Wiki 层（Phase 1）│    │  RAG 层（Phase 3）          │ │
│  │                  │    │                             │ │
│  │  SQLite 表:      │    │  SQLite + sqlite-vec:       │ │
│  │  - user_profile  │    │  - conversation_chunks      │ │
│  │  - partner_wiki  │    │  - embedding vectors        │ │
│  │  - ai_facts      │    │                             │ │
│  │                  │    │  本地 embedding 模型:        │ │
│  │  始终注入上下文   │    │  all-MiniLM-L6-v2 (ONNX)   │ │
│  └──────────────────┘    └─────────────────────────────┘ │
│           │                           │                  │
│  ┌────────┴───────────────────────────┴───────────────┐  │
│  │              Memory Manager (Phase 2)               │  │
│  │                                                     │  │
│  │  提取器: 对话后 LLM 提取事实 → 写入 Wiki            │  │
│  │  整合器: 定期 Dreaming → 合并/去重/衰减             │  │
│  │  检索器: Wiki 始终注入 + RAG 按需召回               │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │           动态系统提示词构建器 (Phase 1)              │  │
│  │                                                    │  │
│  │  Wiki 事实 + 时间感知 + 近期摘要 → 注入 system prompt│  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

#### 3.2 Phase 1：动态系统提示 + 轻量 Wiki（预计 2-3 天）

这是投入产出比最高的阶段，**不需要任何新依赖**，只需改造现有代码。

##### 3.2.1 新增 `ai_memory_service.dart`

核心职责：从现有数据库表收集上下文，构建动态系统提示。

```dart
/// AI 记忆服务 — 构建动态上下文
abstract final class AiMemoryService {

  /// 构建动态系统提示词（替代静态 _chatSystemPrompt）
  static Future<String> buildSystemPrompt() async {
    final sections = <String>[];

    // 1. 基础指令（保留现有格式规则）
    sections.add(_baseInstructions);

    // 2. 用户身份
    final user = await LocalUserService.getUser();
    if (user != null && user.nickname.isNotEmpty) {
      sections.add('用户信息：用户叫${user.nickname}');
    }

    // 3. 关心的人列表（含备注）
    final partners = await PartnerService.getAll();
    if (partners.isNotEmpty) {
      final lines = partners.map((p) {
        final days = DateTime.now().difference(p.createdAt).inDays;
        final note = p.note != null && p.note!.isNotEmpty ? '，备注: ${p.note}' : '';
        final city = p.city != null && p.city!.isNotEmpty ? '，城市: ${p.city}' : '';
        return '- ${p.nickname}（${p.typeLabel}，认识 $days 天$city$note）';
      }).toList();
      sections.add('关心的人：\n${lines.join('\n')}');
    }

    // 4. 活跃提醒
    // ... 从 reminder_configs 读取

    // 5. 时间感知
    final now = DateTime.now();
    final hour = now.hour;
    String timeDesc;
    if (hour < 6) timeDesc = '凌晨';
    else if (hour < 12) timeDesc = '上午';
    else if (hour < 14) timeDesc = '中午';
    else if (hour < 18) timeDesc = '下午';
    else if (hour < 22) timeDesc = '晚上';
    else timeDesc = '深夜';
    sections.add('当前时间：${now.month}月${now.day}日 $timeDesc');

    // 6. 最近对话摘要（Phase 2 扩展）
    // ...

    // 7. Wiki 事实（Phase 2 扩展）
    // ...

    return sections.join('\n\n');
  }
}
```

##### 3.2.2 改造 `ai_service.dart`

将三个方法（`chat`, `streamChat`, `chatWithTools`）中硬编码的 `_chatSystemPrompt` 替换为动态构建：

```dart
// 之前：
{'role': 'system', 'content': _chatSystemPrompt},

// 之后：
final dynamicPrompt = await AiMemoryService.buildSystemPrompt();
{'role': 'system', 'content': dynamicPrompt},
```

`_chatSystemPrompt` 保留为基础指令模板，由 `AiMemoryService` 拼接完整提示。

##### 3.2.3 新增数据库表 `ai_wiki_facts`

```sql
CREATE TABLE ai_wiki_facts (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,      -- 'user_pref' / 'partner_fact' / 'event' / 'relationship'
  entity_id TEXT,              -- 关联的 partner_id 或 null
  content TEXT NOT NULL,       -- 事实内容
  source TEXT DEFAULT 'chat',  -- 'chat' / 'proactive' / 'manual'
  importance REAL DEFAULT 0.5, -- 0.0~1.0
  strength REAL DEFAULT 1.0,   -- 随时间衰减
  access_count INTEGER DEFAULT 0,
  last_accessed TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

这张表在 Phase 1 中仅用于手动存储少量关键事实（如用户在聊天中提到的重要信息），Phase 2 中接入自动提取。

##### 3.2.4 Phase 1 预期效果

改造前后对比：

```
改造前 system prompt:
"你正在用「Ta的世界」APP跟用户聊天...回复规则...示例回复..."

改造后 system prompt:
"你正在用「Ta的世界」APP跟用户聊天...回复规则...示例回复...

用户信息：用户叫小明

关心的人：
- 小红（情侣，认识 180 天，城市: 杭州，备注: 喜欢吃日料）
- 妈妈（家人，认识 365 天，城市: 老家）

活跃提醒：小红有睡觉提醒（22:00）和天气提醒

当前时间：6月12日 晚上"
```

仅这一步改造，就能让 AI 的回复质量和个性化程度产生质的飞跃，且完全零额外 API 成本（只是增加了约 200~500 token 的系统提示）。

---

#### 3.3 Phase 2：对话记忆提取 + Dreaming（预计 3-5 天）

这是让 AI "越用越懂你" 的关键阶段。

##### 3.3.1 对话后事实提取

每次对话结束后（异步，不阻塞用户体验），调用一次轻量级 LLM 提取：

```dart
/// 从对话中提取可记忆的事实
static Future<void> extractMemories(String conversation) async {
  final key = await AiService.getApiKey();
  if (key == null) return;

  // 读取当前 wiki 事实
  final existingFacts = await _getExistingFacts();

  final prompt = '''从以下对话中提取值得记住的事实。

已有的记忆：
$existingFacts

对话内容：
$conversation

提取规则：
1. 只提取有持久价值的信息（偏好、关系、重要事件、健康信息）
2. 忽略日常闲聊和临时状态
3. 如果新信息与已有记忆矛盾，标记为 UPDATE
4. 每条事实简短概括，不超过30字

返回JSON格式：
{"facts": [
  {"content": "事实内容", "category": "user_pref/partner_fact/event/relationship",
   "entity_name": "相关人名或null", "status": "NEW/UPDATE/SAME", "importance": 0.0-1.0}
]}

如果没有值得记住的新信息，返回：{"facts": []}''';

  // 使用 DeepSeek V4 Flash（成本极低）
  // 解析结果，写入 ai_wiki_facts 表
}
```

**成本估算：** 每次提取约 500~1000 input tokens + 200 output tokens ≈ 0.001 元/次，即使用户每天聊 10 次也不到 0.01 元/天。

##### 3.3.2 对话摘要

当对话历史超过一定长度时，生成摘要存储：

```sql
CREATE TABLE ai_conversation_summaries (
  id TEXT PRIMARY KEY,
  summary TEXT NOT NULL,        -- LLM 生成的摘要
  message_count INTEGER,        -- 包含多少条原始消息
  date TEXT NOT NULL,            -- 对话日期
  topics TEXT,                   -- JSON 数组，涉及的话题
  created_at TEXT NOT NULL
);
```

##### 3.3.3 Dreaming（做梦式记忆整合）

利用现有的 WorkManager 后台任务架构，添加一个"每日做梦"任务：

```dart
/// 记忆整合 — 类似 ChatGPT 的 Dreaming
static Future<void> dream() async {
  // 1. 去重：找到相似度 > 0.9 的 fact 对，合并
  // 2. 矛盾消解：同一 entity 的矛盾事实，保留最新的
  // 3. 情景→语义提升：如果某类事件出现 3+ 次，提升为 wiki 事实
  //    例如：用户连续 5 天提到加班 → "用户近期工作压力较大"
  // 4. 衰减：长期未被访问的 fact 降低 strength
  // 5. 清理：strength < 0.1 的 fact 归档（软删除）
}
```

这个任务注册到 `background_tasks.dart`，每天凌晨 3:00 执行一次（与 AI 主动关怀检查类似）。

##### 3.3.4 在 `buildSystemPrompt()` 中注入 Wiki 事实

```dart
// 在 AiMemoryService.buildSystemPrompt() 中添加：
final facts = await _getTopFacts(limit: 20); // 按 importance * strength 排序
if (facts.isNotEmpty) {
  final factLines = facts.map((f) => '- ${f.content}').toList();
  sections.add('你了解的信息：\n${factLines.join('\n')}');
}
```

---

#### 3.4 Phase 3：RAG 向量检索（预计 5-7 天）

这是最复杂的阶段，需要引入本地 embedding 模型和向量数据库。

##### 3.4.1 技术栈选择

| 组件 | 推荐方案 | 理由 |
|------|---------|------|
| Embedding 模型 | `all-MiniLM-L6-v2` via ONNX Runtime | ~90MB，384维，延迟 20-50ms，中文可用 |
| 向量存储 | `sqlite-vec` | 零依赖 SQLite 扩展，与现有数据库无缝集成 |
| 分块策略 | 对话轮次 + 会话摘要 | 每条消息为一个 chunk，每次会话生成摘要 |

##### 3.4.2 新增表结构

```sql
-- 对话 chunks（用于 RAG 检索）
CREATE TABLE conversation_chunks (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,           -- 消息内容
  role TEXT NOT NULL,              -- user / assistant
  conversation_date TEXT,          -- 对话日期
  topics TEXT,                     -- 提取的话题标签
  embedding BLOB,                  -- 384维 float32 向量
  created_at TEXT NOT NULL
);

-- 使用 sqlite-vec 创建虚拟表
CREATE VIRTUAL TABLE vec_conversation_chunks USING vec0(
  id TEXT PRIMARY KEY,
  embedding float[384]
);
```

##### 3.4.3 RAG 检索流程

```
用户发送消息
    ↓
1. 将用户消息通过 embedding 模型转为 384 维向量
    ↓
2. 在 sqlite-vec 中做余弦相似度搜索，取 top-5
    ↓
3. 将 top-5 相关片段注入系统提示的 "相关回忆" 部分
    ↓
4. 调用 DeepSeek API 生成回复
    ↓
5. 异步：将本轮对话存入 conversation_chunks（含 embedding）
```

##### 3.4.4 系统提示中的 RAG 注入

```dart
// 在 AiMemoryService.buildSystemPrompt() 中添加：
final relevantMemories = await _ragSearch(userMessage, topK: 5);
if (relevantMemories.isNotEmpty) {
  final memoryLines = relevantMemories.map((m) => '- ${m.content}').toList();
  sections.add('可能相关的过往对话：\n${memoryLines.join('\n')}');
}
```

##### 3.4.5 Flutter 集成注意事项

ONNX Runtime Mobile 在 Flutter 中的集成方式：

- Android: 通过 `onnxruntime_flutter` 或自定义 Platform Channel
- iOS: CoreML 替代方案（如有需要）
- 备选方案：使用 DeepSeek 的 embedding API（`text-embedding-3-small`），牺牲离线能力换取实现简单

**建议：** 如果 Phase 3 的本地 embedding 集成复杂度过高，可以先用 API-based embedding 作为过渡，后续再迁移到本地模型。

---

### 四、数据库迁移方案

```dart
// database_helper.dart

static const _dbVersion = 4; // Phase 1→3, Phase 2→4

static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    // v1→v2: ai_pending_messages（已完成）
    await db.execute('CREATE TABLE IF NOT EXISTS ai_pending_messages (...)');
  }
  if (oldVersion < 3) {
    // v2→v3: Wiki 事实表（Phase 1/2）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_wiki_facts (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        entity_id TEXT,
        content TEXT NOT NULL,
        source TEXT DEFAULT 'chat',
        importance REAL DEFAULT 0.5,
        strength REAL DEFAULT 1.0,
        access_count INTEGER DEFAULT 0,
        last_accessed TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_conversation_summaries (
        id TEXT PRIMARY KEY,
        summary TEXT NOT NULL,
        message_count INTEGER,
        date TEXT NOT NULL,
        topics TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }
  if (oldVersion < 4) {
    // v3→v4: RAG 向量表（Phase 3）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_chunks (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        role TEXT NOT NULL,
        conversation_date TEXT,
        topics TEXT,
        embedding BLOB,
        created_at TEXT NOT NULL
      )
    ''');
    // sqlite-vec 虚拟表需要确认扩展是否加载
  }
}
```

---

### 五、文件结构规划

```
lib/
  services/
    ai_service.dart                 # 已有，改造：使用动态 prompt
    ai_proactive_service.dart       # 已有，改造：共享 Wiki 上下文
    ai_memory_service.dart          # 新增 Phase 1：记忆管理核心
    ai_memory_extractor.dart        # 新增 Phase 2：对话事实提取
    ai_memory_dreamer.dart          # 新增 Phase 2：Dreaming 整合
    ai_rag_service.dart             # 新增 Phase 3：向量检索
  data/
    local/
      database_helper.dart          # 改造：新增表 + 迁移
    models/
      ai_wiki_fact.dart             # 新增：Wiki 事实模型
      conversation_chunk.dart       # 新增 Phase 3：对话 chunk 模型
```

---

### 六、实施优先级与预期收益

| 阶段 | 工作量 | 新依赖 | 核心收益 |
|------|--------|--------|---------|
| **Phase 1** | 2-3天 | 无 | AI 知道用户是谁、关心谁、现在几点。预计回复质量提升 50%+ |
| **Phase 2** | 3-5天 | 无 | AI 能从对话中学习、记住偏好、越用越懂。每次对话成本增加 <0.01元 |
| **Phase 3** | 5-7天 | ONNX Runtime + sqlite-vec | AI 能回忆具体经历，实现"我记得你上次说过..."的效果 |

**强烈建议先做 Phase 1**——它不需要任何新依赖，改动量小，但效果立竿见影。目前的 AI 就像每天失忆的人，Phase 1 至少让它"认识"用户和用户的关心对象。

---

### 七、与现有功能的协同

#### 7.1 与 Function Calling 的协同

当系统提示中已包含 partner 列表和提醒信息后，AI 可以更智能地决定何时调用工具。比如用户说"帮我给小红设个晚安提醒"，AI 不需要先调用 `get_all_partners` 确认小红的存在——它已经在上下文里了。

#### 7.2 与主动关怀的协同

`AiProactiveService` 构建的丰富上下文应该被持久化到 Wiki 中。当后台评估发现"小红最近天气变化大"，这个信息同时应该被写入 `ai_wiki_facts`，这样下次用户打开聊天时，AI 也"知道"这个信息。

#### 7.3 与成就系统的协同

成就进度可以作为 Wiki 事实的一部分注入上下文："用户已经解锁了7日连续关怀成就"，让 AI 能够主动鼓励和认可用户的行为。

---

### 八、隐私设计

整个记忆系统遵循 TaWorld 的本地优先原则：

- 所有 Wiki 事实和向量数据存储在本地 SQLite
- 对话提取只发送对话内容给 DeepSeek API（不发送完整记忆库）
- 用户可以在设置中查看所有 AI 记忆、删除单条或清空全部
- 记忆提取可选关闭（设置中提供开关）
- 不使用用户记忆数据做任何形式的模型训练

---

### 九、风险与注意事项

1. **Token 预算控制：** 动态系统提示应控制在 500~800 token 以内（DeepSeek V4 Flash 的 1M 上下文完全不是瓶颈，但保持精简是好习惯）
2. **提取质量：** LLM 提取可能产生错误事实。需要设计"用户可纠正"机制 + confidence 阈值
3. **Phase 3 复杂度：** 本地 ONNX 模型在 Flutter 中的集成可能遇到平台兼容问题，建议预留充足调试时间
4. **记忆膨胀：** 需要 Dreaming 机制控制 Wiki 事实总量在 ~500 条以内，超出后检索质量会下降

---

*文档编写于 2026年6月12日。建议在 Phase 1 完成后进行一次效果验证，再决定是否继续推进 Phase 2/3。*
