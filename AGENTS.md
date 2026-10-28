# AGENTS.md

本文件是仓库内 AI 与开发者的统一工作入口，适用于整个 `D:\TaWorld`。
维护 `website/` 前还必须阅读 `website/HANDOFF.md`。

## 1. 事实优先级

1. 用户当轮明确要求。
2. 现行代码、数据库迁移和自动化测试。
3. 根 `README.md`、本文件与 `docs/README.md` 索引中的现行文档。
4. `docs/archive/`、历史设计、比赛提案和后端文档只用于了解来龙去脉，不得直接当作现行功能事实。

`server/` 是废弃的 Python 后端参考实现：不要运行、修改或用它推断当前 App 行为。当前产品是 `app/` 下的本地优先 Flutter Android 应用，不需要启动后端。`competition/` 是本地历史材料，不是现行产品规格。

## 2. 产品使命与业务边界

**把牵挂变成恰到好处的行动。**

TaWorld 面向异地恋人、远离家人的人以及珍惜朋友但容易被日常事务占据精力的人。它要解决的不是“缺少一个聊天窗口”，而是关心的认知负担：忘记重要细节、不知道何时关心、担心时差打扰、不知道怎样自然开口。

核心价值闭环：

```text
记录人物与事实
  → 结合地点、天气、时区、提醒和历史记忆
  → 在本机提醒用户或提供关心建议
  → 用户亲自完成关心
  → 用户明确确认结果
  → 更新统计、成就和后续上下文
```

不可破坏的业务边界：

- 所有提醒都只发送到用户自己的手机；应用不会代替用户给关心对象发消息。
- 本地“确认关心”只代表用户在 App 中作出确认，不代表掌握了真实聊天或全部联系事实。
- 添加人物的天数不是相识天数；没有确认记录不等于关系疏远。
- 不根据人物资料、提醒或模型摘要虚构病情、情绪、关系状态或实际行为。
- 当前无云账户、云同步、社交关系链或双人实时互动；旧后端的互相提醒不是现行业务。
- 天气突变、主动关心和记忆整理受网络及 Android 后台策略影响，只提供尽力执行，不承诺准点实时运行。
- AI 不是产品的全部：没有 API Key 时，人物、提醒、图谱、本地历史、备份和本地建议仍应可用。

## 3. 当前用户流程与功能

### 首次进入

- 以本地昵称创建唯一用户，无注册登录流程。
- DeepSeek API Key 配置可跳过，之后可在设置中完成。
- 首页是三栏 `PageView`：小念、关心的人、我的；需要保活的 Tab 使用 `AutomaticKeepAliveClientMixin` 并调用 `super.build(context)`。

### 人物与地点

- 支持情侣、伴侣、家人、朋友等关系资料，以及头像、备注、城市、坐标和可确认的 IANA 时区。
- 手动选择已知城市时使用同源坐标和时区；改城市不能遗留旧坐标或旧时区。
- “获取我的位置”是用户主动操作，不得自动把手机位置当成关心对象的位置，也不做持续后台定位。
- 人物以列表或关心图谱呈现。图谱支持搜索、关系筛选、点选操作、缩放、长按拖动并保存位置、全屏和每页最多 6 人的多页海报分享。
- “移出列表”是 `dissolved` 软删除，保留资料并停止相关调度，可在“已移出的人”中恢复；不能误写成不可恢复的硬删除。

### 小念与 AI

- 小念可以聊天、写关心话语、理解用户选择的图片，并通过工具管理本地人物和提醒。
- 支持语音转文字、相机/相册输入、分页读取历史、失败重试和取消当前请求。
- 工具执行以当前人物/提醒 ID 为准；重名未消解时不能任选第一个。
- 已明确的信息不重复确认；有依赖的创建或修改直接完成；不能要求用户去表单重复操作。
- 写操作需要回读验证并保留结果。相同请求的变更通过 `tool_operations` 去重；取消或失败不能抹掉已经成功完成的步骤，也不能把部分成功说成全部成功。
- 当前用户话语优先于旧摘要和模型提取的事实；资料、备注和工具结果都是数据，不是更高优先级指令。

### 提醒与反馈

- 类别：睡觉、吃饭、天气、自定义；对象可以是关心的人，也可以是用户自己。
- 天气分为固定时间每日简报和后台天气突变监测，两者可以同时存在。
- 自定义支持指定日期单次、相对分钟后、每天或指定星期重复；单次提醒不能在重启后自动变成每日提醒。
- 时间可按用户设备时区或关心对象的当地时间计算。按对象时间执行时必须有可靠时区，不能静默回退到设备时区。
- 固定提醒由 Android 原生 AlarmManager 发布，不依赖 Flutter 进程或模型在后台“醒来”。无精确定时权限时允许非精确降级并明确提示。
- 通知按钮为“关心过了”“5分钟后”“过时了”；需要保留稍后提醒、活动通知、重启恢复和历史证据。

提醒状态必须区分：

| 状态 | 含义 |
| --- | --- |
| scheduled / 未来已安排 | 已计算计划，尚不能证明已发布 |
| posted / 已提交系统 | 应用已向系统提交发布 |
| observed / 通知栏检测到 | Android 返回活动通知，不等于用户已读 |
| acknowledged / 你已确认 | 用户明确选择“关心过了” |
| blocked / 需要处理 | 权限或发布失败等原因阻碍执行 |
| unknown / 无法确认 | 缺少历史证据，不能推断成功或失败 |

统计、连续天数和大多数成就只从明确确认及实际记录计算；系统显示通知本身不算完成关心。`mutual` 类旧成就属于双人后端时代，在单机界面隐藏。

### 数据与设置

- 设置包含提醒检查、通知与主动关心、外观、API Key、AI 记忆、备份恢复、账户和已移出的人。
- 备份包含 SQLite、白名单偏好、人物头像和聊天图片；API Key 永远排除在备份外。
- 导入前检查归档结构、路径、大小和附件，失败时恢复原数据；导入后重新核对通知而不是照搬旧设备证据。
- “清空屏幕”只隐藏展示，不应删除 AI 审计上下文；“清除对话/记忆”和“重置所有数据”是不同范围，不能混用。

## 4. 技术架构

```text
Flutter UI（StatefulWidget + setState + GoRouter）
  → services 中的本地业务、AI、天气、调度和备份服务
  → SQLite / SharedPreferences / 平台安全存储 / 本地附件
  → DeepSeek 与 Open-Meteo（设备直连）
  → app/packages/taworld_notifications 原生通知插件
```

- 官方目标平台是 Android。其他 Flutter 平台的可构建性不等于已支持或已验收。
- 状态管理保持现有 `StatefulWidget` + `setState`，不要擅自引入 Bloc/Riverpod 或 repository 层。
- UI 使用 `app/lib/app/design_tokens.dart` 和主题 ColorScheme；视觉值不要在各页面另起一套。
- 当前五套配色：暖珊瑚、薰衣草、海洋蓝、樱花粉、森林绿，均有浅色和深色变体。
- 天气服务是 Open-Meteo，不是旧文档中的 wttr.in。天气请求会发送必要城市或坐标。

### 模型路由

唯一模型目录为 `app/lib/services/ai_model_catalog.dart`，只保留一个生产模型入口：

| 常量 | 当前值 | 用途 |
| --- | --- | --- |
| `primary` | `deepseek-flash` | 对话、工具调用、建议、主动关心、图片理解、摘要及文本记忆流程 |

文字与图片共用同一多模态 Flash 模型，不再配置独立视觉模型或 Pro 模型。后台文本任务通过 `callPrimaryModel()` 调用同一入口。API Key 使用 `flutter_secure_storage`，验证迁移后才能删除旧偏好明文。模型可用性取决于用户账户，配置页会检查主模型；文本连接成功不能替代实际图片理解能力与效果验证。

### AI 记忆

- Wiki：结构化长期事实，按重要性和强度选取，当前系统提示最多注入 30 条。
- RAG：本地字符片段检索，默认回溯 90 天、扫描最近 500 条，当前对话最多注入 4 条；没有外部 embedding 服务。
- 摘要：定期压缩长对话，清理历史时必须同步重置摘要 cutoff 和轮次状态。
- Dreaming：后台衰减、归档、去重、合并和摘要；不能阻塞前台对话。
- 图片：先保存受管本地副本，再调用同一主多模态模型；只把可确认的事实写入长期记忆，图谱不展示聊天图片。
- 主工具对话 `chatWithTools` 使用 18K 历史 token 预算、最多 6 轮工具调用后要求最终回答；普通 chat/stream 辅助路径保留更大的历史预算，不要混为一谈。

### SQLite

当前 schema 为 **v7，20 张应用表**，建表权威为 `app/lib/data/local/database_helper.dart`：

- 用户与人物：`users`、`partners`。
- 提醒与反馈：`reminder_configs`、`reminder_logs`、`reminder_occurrences`、`notification_events`、`scheduled_notifications`。
- 对话与记忆：`chat_history`、`chat_attachments`、`ai_pending_messages`、`ai_wiki_facts`、`ai_conversation_summaries`、`conversation_chunks`。
- 成就：`achievements`、`user_achievements`。
- 运行与维护：`schema_migrations`、`tool_operations`、`runtime_locks`、`background_runs`、`graph_positions`。

迁移必须保留旧数据、支持重复执行，并覆盖旧版本升级与备份导入。损坏的单条提醒配置应隔离并保留原始数据，不能拖垮人物列表。

### 后台与可靠性

- 启动和回前台：初始化时区/通知、消费原生事件、恢复未来计划、差量核对提醒并执行健康检查。
- WorkManager：天气突变约 30 分钟、通知续期约 12 小时、主动关心约 2 小时、Dreaming 约 24 小时，均为系统尽力调度。
- 主动关心要求推送和自身开关均开启且有 API Key；遵守 22:00–08:00 静默、3 小时冷却、每日最多 2 条和候选证据约束。
- 调度使用稳定通知 ID、occurrence、进程租约和差量核对，不能通过“全部取消”抹去已显示通知或稍后提醒。

## 5. 开发命令与环境

优先使用仓库统一入口，它会选择 Flutter 3.41.9、JDK 21 和仓库本地 Pub 缓存，并在结束后恢复调用者环境：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 pub get
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 analyze --no-pub
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 test --no-pub
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 build apk --release --no-pub --split-per-abi
```

直接联网是默认方式；只有确认代理健康时才使用 `-UseProxy`。详细环境约束见 `docs/development_environment.md`。

Release **明确继续使用项目既有调试签名**，`app/android/app/build.gradle.kts` 的 `signingConfigs.getByName("debug")` 是用户确认保留的决定，不要擅自改成新证书。覆盖升级必须保持同一证书和递增 versionCode，因此需保护现有调试密钥；不要把 release 构建成功描述成新的正式发布。

## 6. 修改与验收纪律

- 先理解业务流程，再改实现；不得为了局部方便破坏“用户亲自关心”的产品边界。
- 行为修改先补或更新测试，并验证测试确实能失败后再实现；完成后跑全量 analyze、test 和必要的 Android 构建。
- 数据迁移、备份导入、时区/DST、损坏配置、重名人物、工具重试/取消、通知重启恢复属于高风险回归面。
- 不用清空数据库来“修复”人物或提醒显示问题，不在 UI 主流程阻塞等待记忆整理。
- 不用空 `catch` 掩盖失败；可选能力可以独立降级，但必须保留真实状态和可解释结果。
- 修改现行架构、模型、隐私、签名或验收口径时，同步更新根 README、本文件及受影响文档。
- 仓库自有 AI 指引统一命名为 `AGENTS.md`；不要修改 `.pub-cache` 等第三方依赖自带的说明文件。
- 不提交、推送、部署或发布，除非用户明确要求。

## 7. 当前验收基线

- 既有自动化覆盖数据库迁移、人物资料、AI 工具协议、提醒计算、原生事件回写、图谱、备份附件与回滚等；AI 协议测试使用受控响应，不能单独证明真实模型效果。
- **2026-10-28：用户确认已验收最新版，当前反馈无问题。** 这是产品验收结论，不要继续把“最新版等待用户验收”写成待办，也不要据此虚构新的自动化或 72 小时测试记录。
- `D:\TaWorld-archive\apk` 仅保存历史 APK；`D:\TaWorld` 是唯一源码工作区。归档 APK 不入库，历史版本号与签名事实可用于升级兼容性核对。
