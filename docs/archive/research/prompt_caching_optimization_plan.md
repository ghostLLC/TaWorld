# DeepSeek 上下文缓存优化方案

## DeepSeek 缓存机制原理

DeepSeek 的「上下文缓存」（Context Caching）是**服务端 KV Cache 复用**，不是客户端缓存。

工作原理：DeepSeek 将所有 messages 序列化成一个完整的 token 流（通过 chat template 拼接，类似 `<|im_start|>system\n...<|im_end|><|im_start|>user\n...<|im_end|>`），然后从第 0 个 token 开始，以 **64 token 为一个块**，逐块与之前请求的 token 流做精确前缀匹配。匹配的块复用已计算的 KV 状态，不匹配的块重新计算。

关键特性：
- **完全自动**，不需要任何 API 参数或 header
- **token 级匹配**，不关心消息边界（system/user/assistant 一视同仁）
- 响应中通过 `usage.prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` 报告命中情况
- 缓存命中时输入价格：V4-Flash **0.02 元/M**（原价 1 元，**1/50**），V4-Pro **0.025 元/M**（原价 3 元，**1/120**）
- TTL 数小时到数天，不可配置，不可保证

## 当前请求的 token 流分析

以 `streamChat()` 为例，DeepSeek 收到的 token 流：

```
[system prompt ~1400t] [history turn 1 ~80t] [history turn 2 ~80t] ... [history turn N] [当前 user msg ~30t]
```

系统提示 8 个区块的 token 分布：

```
 token 0 ──── token 400 ──── 420 ──── 620 ──── 770 ──── 795 ──── 1145 ──── 1265 ──── 1385
 │             │              │        │        │        │         │         │         │
 ▼             ▼              ▼        ▼        ▼        ▼         ▼         ▼         ▼
 _baseInst.    用户身份        伴侣列表   活跃提醒   当前时间⚡  Wiki事实    对话摘要    RAG结果
 ~400t STATIC  ~20t 极少变     ~200t 少变 ~150t 少变 ~25t/分钟  ~350t 会话级  ~120t 天级   ~120t/条消息
```

**⚡ = 缓存杀手**：`当前时间` 精确到分钟，位于第 770 token 处。用户连续发两条消息（比如 15:30 和 15:31），前缀在 token 770 处断裂，后面的 Wiki 事实（350t）、摘要（120t）全部无法缓存。

以 64 token 块计算：
- 可缓存前缀 = token 0~769 = 12 个块 = 768 token
- 不可缓存 = token 770 起 = 617 token + history + user msg

如果两次请求跨分钟（常见场景），**有效缓存只有前 4 个区块**（~770t，12 块）。

## 优化方案（仅涉及 DeepSeek 服务端缓存）

### 改动 1：时间粗化 + 位置后移

**解决什么问题**：时间区块在第 770 token 处每分钟变一次，截断了后面所有区块的缓存机会。

**怎么改**：
1. 去掉分钟精度，只保留日期 + 时段（`2026年6月12日 下午`），每 3-6 小时才变一次
2. 把时间区块从第 5 位挪到第 7 位（Wiki 和摘要之后，RAG 之前）

**改后的 token 流**：

```
 token 0 ──── 400 ──── 420 ──── 620 ──── 770 ──── 1120 ──── 1240 ──── 1260 ──── 1380
 │             │        │        │        │         │         │         │         │
 ▼             ▼        ▼        ▼        ▼         ▼         ▼         ▼         ▼
 _baseInst.    用户     伴侣     提醒     Wiki事实    摘要      时间(粗)    RAG
 ~400t         ~20t     ~200t    ~150t    ~350t      ~120t     ~20t/3h    ~120t/msg
```

**效果**：
- 可缓存前缀从 768t 扩展到 1240t = **19 个块**（原来 12 块 → 增加 58%）
- 同一时段内的连续对话，系统提示部分命中率 ~85%
- 而且因为 system prompt 稳定了，后面的 chat history 也能缓存（history 天然是 append-only 的）

**涉及的代码变更**：仅 `ai_memory_service.dart` 的 `buildSystemPrompt()` 方法

```dart
// 原来（位置 5，精确到分钟）：
sections.add('【当前时间】\n${now.year}年${now.month}月${now.day}日 $timeDesc ${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');

// 改为（位置 7，只保留时段）：
// ... 先添加 Wiki 和摘要 ...
sections.add('【当前时间】\n${now.year}年${now.month}月${now.day}日 $timeDesc');
```

### 改动 2：V4 Pro 后台任务拆分 system/user 消息

**解决什么问题**：`callProModel()` 把所有内容打包成一条 user message（见 `ai_service.dart` 第 622-624 行），指令部分和数据部分混在一起。Dreaming 按类别调 4-5 次，每次指令（~300t）完全相同但无法被 DeepSeek 缓存，因为它们在 token 流中的位置不同（前面拼了不同的类别数据）。

**怎么改**：把不变的指令放到 system message，可变的数据放到 user message。

改后 DeepSeek 看到的 token 流（以 Dreaming 4 个类别为例）：

```
调用 1: [system: 整合指令 ~300t] [user: 类别=user_pref, 事实列表 ~200t]
调用 2: [system: 整合指令 ~300t] [user: 类别=partner_fact, 事实列表 ~300t]
调用 3: [system: 整合指令 ~300t] [user: 类别=event, 事实列表 ~150t]
调用 4: [system: 整合指令 ~300t] [user: 类别=relationship, 事实列表 ~100t]
```

system 部分完全相同 → DeepSeek 缓存 300t = 4 个块，后 3 次调用全部命中。

**涉及的代码变更**：

`ai_service.dart` 的 `callProModel()`：

```dart
// 原来：
'messages': [
  {'role': 'user', 'content': prompt},
],

// 改为接受可选 systemPrompt 参数：
'messages': [
  if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
  {'role': 'user', 'content': prompt},
],
```

`ai_memory_extractor.dart` 和 `ai_memory_dreamer.dart`：把指令部分从 prompt 中提取出来作为 systemPrompt 传入。

### 改动 3：缓存命中率监控

**解决什么问题**：目前完全无法观察缓存是否生效，无法验证优化效果。

**怎么改**：解析 API 响应中的 `usage` 字段，记录并展示缓存统计。

DeepSeek 响应格式：
```json
{
  "usage": {
    "prompt_tokens": 2000,
    "prompt_cache_hit_tokens": 1280,
    "prompt_cache_miss_tokens": 720,
    "completion_tokens": 150
  }
}
```

**涉及的代码变更**：

`ai_service.dart`：在 `chat()`、`streamChat()`、`chatWithTools()` 的响应解析中提取 `prompt_cache_hit_tokens` 和 `prompt_cache_miss_tokens`，debugPrint 输出或累计到 SharedPreferences 供设置页展示。

## 预期费用节省

### 场景：用户每天对话 20 轮（V4-Flash），30 天/月

| 项目 | 优化前 | 优化后 |
|------|:-----:|:-----:|
| 每轮系统提示 token | ~1,400（全 miss） | ~1,400（85% hit） |
| 每日系统提示输入费 | 0.028 元 | 0.0047 元 |
| 每月系统提示输入费 | **0.84 元** | **0.14 元** |
| 节省 |  | **83%** |

> 计算：优化后 85% hit → 1,190t × 0.02 + 210t × 1.0 = 23.8 + 210 = 233.8 元/M → 0.0047 元/次（按每轮 1,400t）
> 加上 history 部分的缓存收益（稳定 system prompt 后 history 前缀也能命中），实际节省可能更大。

### V4-Pro 后台任务（Dreaming + 提取）

| 任务 | 调用次数 | 优化前 | 优化后 |
|------|:-------:|:-----:|:-----:|
| Dreaming 整合（4 类别） | 4-5/天 | 0.048 元/天 | 0.012 元/天 |
| 事实提取（每次对话后） | 20/天 | 0.024 元/天 | 0.018 元/天 |

> Pro 任务总量少，绝对金额不大，但缓存命中后价格仅为原价的 1/120，积少成多。

## 实施顺序

| 步骤 | 改动 | 涉及文件 | 复杂度 |
|:---:|------|---------|:-----:|
| 1 | 时间粗化 + 位置后移 | `ai_memory_service.dart` | 低 |
| 2 | Pro 任务拆分 system/user | `ai_service.dart` + `ai_memory_extractor.dart` + `ai_memory_dreamer.dart` | 低 |
| 3 | 缓存命中率监控 | `ai_service.dart` + `settings_screen.dart` | 低 |

三个改动互相独立，可逐步实施、逐步验证。
