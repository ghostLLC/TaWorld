# TaWorld 当前技术架构

> 状态：现行文档，对应 v0.2.0（0.2.0+4）与 SQLite schema v7。

## 1. 产品形态与边界

TaWorld 是本地优先的 Flutter Android 关怀助手。它记录人物、地点、提醒、对话和记忆，在用户自己的手机上提示关心时机；实际联系由用户亲自完成。

当前没有云账户、云同步、双人实时关系链或业务服务器。`server/` 是废弃参考实现，不参与构建、运行或当前数据流。

核心业务闭环：

```text
人物与事实 → 地点/天气/时区/记忆 → 本机提醒或建议
  → 用户亲自关心 → 用户明确确认 → 统计、成就与后续上下文
```

## 2. 总体结构

```text
Flutter UI（StatefulWidget + setState + GoRouter）
  ├─ 小念、人物列表/图谱、提醒、成就、设置
  ├─ AI 工作流与工具操作日志
  ├─ 提醒计算、差量调度、后台评估
  └─ 备份校验、附件映射、导入回滚
        │
        ├─ SQLite / SharedPreferences / 本地图片
        ├─ flutter_secure_storage（仅 API Key）
        ├─ DeepSeek（设备直连，deepseek-flash）
        ├─ Open-Meteo（设备直连）
        └─ taworld_notifications 原生插件
              AlarmManager → 通知栏 → 动作/系统事件 → 本地账本
```

主要目录：

- `app/lib/app/`：应用入口、路由、主题、字体、设计令牌。
- `app/lib/data/`：模型、城市坐标和 SQLite 初始化/迁移。
- `app/lib/services/`：AI、记忆、天气、提醒、通知、备份和本地业务服务。
- `app/lib/presentation/`：页面与通用组件。
- `app/packages/taworld_notifications/`：Android 原生发布、动作和重启恢复。
- `app/test/`：数据库、服务、协议和 widget 回归测试。

## 3. 模型与 AI 工作流

唯一生产模型目录是 `app/lib/services/ai_model_catalog.dart`：

| 入口 | 模型 | 用途 |
| --- | --- | --- |
| `AiModelCatalog.primary` | `deepseek-flash` | 对话、工具调用、主动关心、图片理解、建议、摘要与记忆处理 |

不再配置独立视觉模型或 Pro 模型。`callPrimaryModel()` 处理后台文本任务，图片请求也使用同一 `primary`。

主工具对话具备：

- 当前人物/提醒 ID 和结构化时钟；
- 最多 6 轮工具调用后生成最终回答；
- 写操作回读验证、部分成功状态和操作里程碑；
- 相同请求的变更去重、取消、超时和安全重试；
- 重名消歧、单次/每日/指定星期提醒和可靠时区约束。

AI 不是本地功能的必要条件。无 API Key 时，人物、提醒、图谱、历史、备份和本地建议仍可用。

## 4. AI 记忆

- **Wiki**：长期事实，当前最多注入 30 条，按重要性和强度排序。
- **RAG**：本地字符片段检索，默认回溯 90 天、扫描最近 500 条，当前对话最多注入 4 条。
- **摘要**：压缩长对话；清理历史时同步重置 cutoff 与轮次状态。
- **Dreaming**：后台衰减、归档、去重、合并和摘要，不能阻塞前台。
- **图片**：用户主动选择后保存受管副本，使用同一多模态模型提取可确认事实。

模型记忆是辅助数据，不是绝对事实。当前用户更正优先于旧摘要和模型提取结果。

## 5. 提醒与通知可靠性

提醒类别为睡觉、吃饭、天气、自定义，可针对人物或用户自己。天气分为每日简报和突变监测，自定义支持单次、相对分钟、每日及指定星期。

时间可以跟随设备或人物的可靠 IANA 时区。按人物时间执行时，不得静默回退到设备时区；界面中的时间显示与调度共用相同语义。

关键数据职责：

- `reminder_configs`：长期提醒规则。
- `reminder_occurrences`：某一次具体提醒实例。
- `notification_events`：系统提交、通知栏观测、权限失败和用户动作证据。
- `reminder_logs`：面向历史、统计和成就的确认记录。
- `scheduled_notifications`：稳定通知 ID 与排程指纹。

状态不得混淆：已安排、已提交系统、通知栏检测到、用户确认、需要处理、无法确认分别代表不同证据。通知栏出现不等于用户已读；用户确认也不代表应用掌握真实联系记录。

固定提醒由 Android AlarmManager 发布，不依赖 Flutter 进程或模型后台运行。无精确定时权限时允许非精确降级并明确提示。

## 6. SQLite 与本地文件

当前 schema 为 **v7，共 20 张应用表**：

- 用户人物：`users`、`partners`。
- 提醒证据：`reminder_configs`、`reminder_logs`、`reminder_occurrences`、`notification_events`、`scheduled_notifications`。
- 对话记忆：`chat_history`、`chat_attachments`、`ai_pending_messages`、`ai_wiki_facts`、`ai_conversation_summaries`、`conversation_chunks`。
- 成就：`achievements`、`user_achievements`。
- 运行维护：`schema_migrations`、`tool_operations`、`runtime_locks`、`background_runs`、`graph_positions`。

迁移必须保留数据、支持重复执行，并覆盖旧版本升级和备份导入。损坏的单条提醒配置需要隔离，不能拖垮人物列表。

人物“移出”是可恢复软删除；聊天“清空屏幕”只隐藏展示；清除记忆、清除对话和重置全部数据具有不同范围。

## 7. 后台任务

WorkManager 任务均为系统尽力调度：

| 任务 | 频率意图 | 说明 |
| --- | --- | --- |
| 天气突变检查 | 约 30 分钟 | 需要网络，受 Doze/厂商策略影响 |
| 通知续期 | 约 12 小时 | 补充未来提醒窗口 |
| AI 主动关心 | 约 2 小时 | 受开关、静默、冷却、每日上限和候选证据约束 |
| AI Dreaming | 约 24 小时 | 记忆衰减、合并和摘要 |

主动关心遵守 22:00–08:00 静默、3 小时冷却和每日最多 2 条，不制造内疚或虚构关系状态。

## 8. 安全、隐私与备份

- 业务数据保存在 SQLite 和本地私有目录。
- API Key 由 `flutter_secure_storage` 保存，不进入备份。
- AI 请求会发送必要对话、人物、记忆或用户选择的图片。
- 天气请求会发送必要城市或坐标，不进行持续后台定位。
- 备份包含数据库、白名单偏好、人物头像与聊天图片；导入执行结构、路径、大小和附件校验，并可回滚。
- 恢复后重新核对通知，不照搬旧设备发布证据。

## 9. UI 与发布

UI 使用 `StatefulWidget + setState`，不引入 Bloc/Riverpod。五套主题具有浅色和深色变体；primary、secondary、tertiary 的浅色前景对比度要求至少 4.5:1。列表动画延迟有上限，修改过的加载、思考、庆祝和按钮动画支持减少动态效果。

Release 明确沿用现有调试签名，覆盖升级必须保持同证书并递增 versionCode。详细验证见 `testing.md`，发布说明见 `releases/v0.2.0.md`。
