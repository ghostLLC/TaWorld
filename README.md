# TaWorld

<p align="center">
  <strong>把牵挂变成恰到好处的行动</strong><br>
  一款以「关心身边的人」为核心的本地优先 AI 助手
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.1.1-E89186" alt="Version v0.1.1">
  <img src="https://img.shields.io/badge/Flutter-3.41.9-02569B?logo=flutter&logoColor=white" alt="Flutter 3.41.9">
  <img src="https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

<p align="center">
  <a href="https://taworld-cloud1-8grf0qgi8c6c0603.webapps.tcloudbase.com">🌐 产品官网</a> ·
  <a href="https://ghostllc.github.io/TaWorld/">GitHub Pages 镜像</a> ·
  <a href="https://github.com/ghostLLC/TaWorld/releases/download/v0.1.1/TaWorld-v0.1.1-arm64-v8a.apk">下载 v0.1.1 APK（arm64）</a>
</p>

TaWorld 不会替用户联系任何人，而是在合适的时间提醒用户主动关心 Ta。人物、提醒、对话与长期记忆保存在设备本地；应用不依赖自建业务服务器，AI 与天气请求由设备直接访问对应服务。

## v0.1.1 主要能力

- **小念 AI 助手**：默认使用 `deepseek-v4-flash`，支持自然对话、主动提问、工具调用及 Wiki + RAG 长期记忆。
- **人物与关心图谱**：以用户为中心展示人物、关系、地点、当地时间、天气与提醒；支持列表、图谱、全屏拖拽缩放、关系编辑和分享海报。
- **多类型提醒**：支持睡觉、吃饭、每日天气、天气突变及自定义提醒，并正确处理人物所在地的 IANA 时区。
- **提醒闭环**：通知可直接选择“知道了”“稍后提醒”或“忽略”；应用记录响应并提供后访，便于修改或清理过时提醒。
- **天气关心**：后台每 30 分钟检查全部关心人物所在地天气，在符合规则时发出变化提醒。
- **语音与图片输入**：支持语音转文字、相机和相册输入；图片由 `deepseek-v4-flash-vision-exp` 理解，提取出的事实可进入本地长期记忆。
- **可靠备份恢复**：备份包含数据库与本地图片附件；导入前执行结构与路径校验，失败时自动回滚，避免覆盖现有数据。
- **温暖而克制的界面**：紧凑导航、轻量动效、柔和层次与五套主题配色，兼顾浅色和深色模式。

> 当前版本暂不在关心图谱中展示用户上传的图片；图片仅用于对话理解和本地记忆，便于控制备份体积与升级风险。

## 产品原则

| 原则 | 说明 |
| --- | --- |
| 人是连接的桥梁 | TaWorld 提醒 A 关心 B，不会直接联系 B |
| 本地优先 | 核心业务数据保存在设备 SQLite 中，不依赖自建后端 |
| 主动但不打扰 | 结合人物时区、天气变化和提醒状态，在合适时机提供帮助 |
| 简洁可解释 | 关键操作给出明确反馈，提醒和 AI 工具执行结果可追踪 |
| 升级可恢复 | 数据库迁移、备份校验与失败回滚共同保护用户数据 |

## 技术架构

```text
Flutter UI
   │
   ├── 对话 / 人物 / 图谱 / 提醒 / 设置
   │
Service Layer
   ├── AI 对话、工具规划、记忆提取与 RAG
   ├── 天气查询、变化监测与后台任务
   ├── 本地通知、提醒调度与响应后访
   └── 备份归档、导入校验与失败回滚
   │
Local Data
   ├── SQLite（schema v6）
   └── 本地图片与配置
   │
   ├── DeepSeek API（设备直连）
   └── 天气服务（设备直连）
```

### 核心技术

| 范围 | 技术与说明 |
| --- | --- |
| 客户端 | Flutter 3.41.9、Dart、Material 3 |
| 数据 | sqflite，本地数据库 schema v6 |
| AI | `deepseek-v4-flash`；图片理解使用 `deepseek-v4-flash-vision-exp` |
| 记忆 | Wiki 事实、对话摘要、关键词 RAG 与后台整理 |
| 通知 | flutter_local_notifications、时区化调度、通知操作按钮 |
| 后台 | WorkManager，天气检查与维护任务 |
| 输入 | speech_to_text、相机与相册 |
| 网络 | Dio，AI 与天气服务由客户端直接请求 |

## 本地开发

### 环境要求

- Flutter 3.41.9 或兼容版本
- Android Studio 自带 JDK 21
- Android 真机或模拟器

Windows 上如果 Flutter、项目和 Gradle 缓存位于不同盘符，项目已在 `app/android/gradle.properties` 中关闭 Kotlin 增量编译及 classpath snapshot，以规避跨盘缓存路径错误。

### 运行与检查

```bash
cd app
flutter pub get
flutter analyze --no-pub
flutter test
flutter run
```

### 构建 APK

```bash
cd app
flutter build apk --release --split-per-abi
```

当前开发阶段的 release APK 仍使用调试签名；正式分发前应配置独立发布密钥、密钥保护和稳定升级签名流程。

## 当前质量基线

- `flutter analyze --no-pub`：0 个问题
- `flutter test`：169 项测试全部通过
- Android split release：`armeabi-v7a`、`arm64-v8a`、`x86_64` 构建通过
- 数据库迁移：覆盖人物时区、提醒响应记录及 v6 schema
- 备份导入：覆盖格式校验、附件恢复、路径重写和失败回滚

## 隐私说明

- 人物、提醒、消息、记忆和附件默认保存在设备本地。
- 应用不提供云同步，也不通过自建服务器中转业务数据。
- 用户发起 AI 对话或图片理解时，相关文本或图片会直接发送到其配置的 DeepSeek 服务。
- 天气查询会把所需城市信息直接发送到天气服务。
- 定位仅用于用户明确使用的地点或天气功能；应用不主动联系任何关心对象。
- 用户应妥善保管 API Key 与本地备份文件。

## 项目状态

TaWorld 仍处于早期开发阶段。v0.1.1 完成了体验闭环、提醒时区、后台天气监测、语音/图片输入、关心图谱以及本地数据兼容性的第一轮落地，后续将继续优化视觉质感、交互细节和真实设备稳定性。

---

<p align="center">Made with care by TaWorld Team</p>
