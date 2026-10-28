# TaWorld

<p align="center">
  <strong>把牵挂变成恰到好处的行动</strong><br>
  一款以「关心身边的人」为核心的本地优先 AI 助手
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.2.0-E89186" alt="v0.2.0">
  <img src="https://img.shields.io/badge/Flutter-3.41.9-02569B?logo=flutter&logoColor=white" alt="Flutter 3.41.9">
  <img src="https://img.shields.io/badge/platform-Android-3DDC84?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

[产品官网](https://taworld-cloud1-8grf0qgi8c6c0603.webapps.tcloudbase.com) · [GitHub Pages 镜像](https://ghostllc.github.io/TaWorld/) · [下载 v0.2.0](https://github.com/ghostLLC/TaWorld/releases/tag/v0.2.0) · [文档索引](docs/README.md)

TaWorld 帮你记住人物资料，在合适的时间提醒你关心 Ta。人物、提醒、对话、记忆与附件保存在设备本地；AI 和天气请求由设备直接访问对应服务。应用不会代替用户联系关心对象。

当前发布版本为 **v0.2.0（0.2.0+4）**。本版完成数据可靠性、提醒反馈、关心图谱、模型执行流程、单一多模态路由、主题与可访问性改造。2026-10-28，用户确认已验收最新版并反馈无异常。

## 主要能力

- **小念对话**：自然语言管理人物与提醒，结合 Wiki 事实、对话摘要和关键词检索。文字与图片理解统一使用多模态模型 `deepseek-flash`；实际可用性取决于账户，设置时会做能力检查。
- **人物档案**：关系、地点、备注与头像；编辑保护未保存草稿，支持恢复已移出的人。
- **提醒**：睡觉、三餐、天气与自定义提醒。自定义支持指定日期单次执行、每天或指定星期重复；按用户或人物已确认的时区计算。
- **通知回应**：在通知栏选择“关心过了”“5分钟后”“过时了”。用户确认与系统发布分别记录。
- **主动关心**：结合已知事实评估，遵守总开关、静默时段、冷却时间和每日上限。没有模型、条件不满足或检查失败时保留可解释状态。
- **输入与主题**：语音转文字、相机 / 相册输入，五套配色及浅色 / 跟随系统 / 深色模式；语义前景对比度、触控尺寸与减少动态效果有回归覆盖。
- **本地备份**：数据库、人物头像与聊天图片；导入前校验结构、路径和附件限制，导入失败可回滚。密钥需要在新设备重新配置。

## v0.2.0 解决的体验问题

| 范围 | 改动 |
| --- | --- |
| 数据可靠性 | 人物独立加载；损坏提醒逐条隔离；字段清空与不修改分离；最新聊天优先并可翻页；人物移出后可恢复；重置数据回到首次引导 |
| 地点与时间 | 已知城市使用同源坐标和时区；改城市清除旧坐标；列表与图谱共用可靠时区，未知状态不估算 |
| 关心图谱 | 稳定位置与颜色、关系筛选、搜索定位、点选操作、缩放、长按拖动、全屏及多页海报 |
| AI 工作流 | 单一 `deepseek-flash` 多模态入口；最多 6 轮依赖工具调用；写后验证、重试去重、取消与超时处理 |
| 提醒闭环 | Android 原生发布与通知按钮；稳定 ID、差量排程、重启恢复；系统证据与用户确认分别记录 |
| 前端体验 | 五套主题高对比前景、暗色语义统一、48px 常用触控目标、精简首屏、提醒配置分层及减少动态效果 |
| 隐私与备份 | 密钥存入平台安全存储并排除在备份外；头像与聊天附件统一备份、校验和回滚 |
| 可维护性 | 统一 AGENTS 与现行文档索引，历史后端和研究资料集中归档，MIT LICENSE 与 v0.2.0 发布说明齐备 |

## 怎样核对提醒

进入小念首页的提醒检查卡，或打开 **我的 → 设置 → 提醒检查**：

| 状态 | 代表什么 |
| --- | --- |
| 未来已安排 | 系统中存在待执行计划，还没有显示证据 |
| 已提交系统 | 应用调用了通知发布接口 |
| 通知栏检测到 | Android 返回了本应用的活动通知，不能据此断言用户已阅读 |
| 你已确认 | 用户选择了“关心过了” |
| 无法确认 | 历史事件缺失，不能认定成功或失败 |
| 已暂停 / 需要处理 | 应用开关或系统权限影响提醒，可在页面查看并修复 |

“修复未来提醒”核对未来计划，不批量补发过期提醒。测试通知也遵守提醒总开关。关闭通知后，原始人物和提醒配置仍保留。

固定时间提醒由 Android 本地闹钟负责。天气变化和 AI 主动关心使用系统后台任务，运行时机受省电、Doze、厂商策略和网络影响，不能保证每 30 分钟准时执行。系统“强行停止”与普通进程回收是不同条件。

## 架构与数据

```text
Flutter UI
  ├─ 对话 / 人物 / 图谱 / 提醒 / 自检 / 设置
  ├─ AI 工作流、工具操作日志、记忆与检索
  ├─ 地点解析、提醒计算、差量调度、后台评估
  └─ 备份校验、附件清单、导入回滚、重置
        │
  SQLite schema v7 + 本地附件 + 平台安全密钥存储
        │
  Android 原生通知插件
    AlarmManager → 通知栏 → 动作 / 发布事件 → 本地账本 → 前台自检
```

| 范围 | 技术与约束 |
| --- | --- |
| 客户端 | Flutter 3.41.9、Dart 3.11、Material 3、StatefulWidget/setState |
| 数据 | sqflite，schema v7，20 张应用表 |
| 模型 | 文字与图片统一 `deepseek-flash`，设备直连 |
| 原生通知 | `app/packages/taworld_notifications`；原生 Receiver 发布、稍后操作与重启恢复 |
| 调度 | 稳定 ID、增量核对、进程租约；精确定时未授权时使用非精确调度 |
| 后台 | WorkManager，天气检查、主动关心评估与记忆维护 |
| 密钥 | flutter_secure_storage；验证迁移成功后移除旧偏好中的明文密钥 |
| 天气 | Open-Meteo；发送必要城市或坐标 |
| 输入 / 备份 | speech_to_text、相机与相册；带资产映射的备份归档 |

`app/` 是当前单机产品。运行本应用不需要启动仓库中的 `server/`；该目录仅为废弃参考实现。

## 本地开发

需要 Flutter 3.41.9、Android SDK、JDK 21、Android 模拟器或手机。优先使用统一入口：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 pub get
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 analyze --no-pub
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 test --no-pub
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/taworld.ps1 build apk --release --no-pub --split-per-abi
```

统一脚本会选择项目要求的 Flutter/JDK 和本地 Pub 缓存，并恢复调用者环境。项目已关闭 Kotlin 增量编译及 classpath snapshot，以规避跨盘缓存路径问题。详细说明见 `docs/development_environment.md`。

## 验证状态（2026-10-28）

- 静态分析：0 项问题；自动测试：**225 项通过**。
- Android release：`armeabi-v7a`、`arm64-v8a`、`x86_64` 分 ABI 构建通过。
- 覆盖：数据库迁移、损坏配置、城市与时区、同名对象、工具重试与取消、多轮依赖、提醒锁恢复、备份资产与回滚、确认统计与成就进度。
- 前端回归：五套浅色主题语义前景对比度、48px 图标按钮、暗色组件、390px 与 200% 字体、健康卡显隐、提醒配置、减少动态效果和成就首次静默。
- 既有 Android 16 / API 36 模拟器已验证覆盖升级、Flutter 进程结束后的提醒、通知栏回应、稍后提醒重启恢复和暂停开关。

AI 协议测试使用受控响应，不能替代真实模型效果评估；自动测试也不等于覆盖所有厂商后台策略或连续 72 小时通知表现。用户验收是产品使用结论，不表示上述自动化项目新增了真实模型或长时间后台覆盖。

本发布明确沿用项目既有调试签名，这是用户确认保留的决定。覆盖升级必须保持同一证书并递增 versionCode，因此需保护现有调试密钥。GitHub tag 与 Release 是本版本的正式发布记录。

## 文档与发布

- [文档索引](docs/README.md)：现行架构、前端、设计、环境、测试和发布资料。
- [v0.2.0 发布说明](docs/releases/v0.2.0.md)：版本改动、资产和证据边界。
- [前端审查记录](docs/design-audit/2026-10-28-frontend-review.md)：问题、修复和暂缓事项。
- [历史归档](docs/archive/README.md)：旧后端与研究资料，不是现行规格。

## 隐私与恢复

- 业务资料、消息、记忆和附件默认保存在设备本地，没有内建云同步。
- AI 对话、图片理解及开启后的主动关心 / 记忆整理，会把相关必要上下文发送给配置的模型服务。
- 天气查询会发送所需坐标或城市；地点功能不会主动联系任何人。
- API Key 使用平台安全存储，不写入备份；本地备份含私人资料，应由用户妥善保存。
- 人物“移出列表”可恢复；“重置所有数据”会清除本机资料、密钥、受管附件及提醒，应先按需要导出备份。
- 升级保留数据库并执行迁移。安装新版本前，建议导出一份可用备份；不要通过清空数据来排查人物显示问题。
