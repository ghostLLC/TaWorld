# 🫶 Ta的世界（TaWorld）

<p align="center">
  <strong>一款以「关怀」为核心的情感连接 APP</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.41.9-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

> 这是一款**完全离线运行**的单机 APP。你添加关心的人，配置提醒，APP 会在合适的时刻**提醒你去关心 Ta**——而不是直接联系对方。所有数据都保存在你手机上，没有服务器，没有云端，安安静静的。
>
> AI 助手（DeepSeek）会主动给你推送天气预警、问候和关怀建议，让每一次关心都更有温度 🌤️

## ✨ 核心功能

| 功能 | 说明 | 状态 |
|------|------|------|
| 🤖 **AI 关怀助手** | DeepSeek AI 驱动的对话式助手，主动推送天气预警、问候语、关怀建议 | ✅ 已完成 |
| 👥 **关心的人管理** | 添加/编辑/删除关心的人，支持 GPS 定位 + 城市选择器（24 个国家，300+ 城市） | ✅ 已完成 |
| 🔔 **智能提醒** | 天气/睡觉/吃饭/自定义提醒，本地精确调度，WorkManager 后台保活 | ✅ 已完成 |
| 🌦️ **实时天气** | wttr.in 免费天气（无需 Key），卡片显示对方城市、当地时间、实时天气 | ✅ 已完成 |
| 🏆 **成就系统** | 7 个成就徽章，4 种解锁逻辑（count/streak/mutual/relationship_days），无积分 | ✅ 已完成 |
| 🌍 **城市选择器** | 底部弹窗模式，支持搜索+浏览，24 个国家 300+ 城市，默认中国 | ✅ 已完成 |
| 📍 **GPS 定位** | geolocator + permission_handler，三级权限检查（GPS 服务→权限申请→获取位置） | ✅ 已完成 |
| 📊 **数据统计** | 提醒总数、连续天数、分类汇总 | ✅ 已完成 |

### 核心设计理念

```
🫶 人是桥梁    APP 不直接提醒 B，而是提醒 A 去关心 B
🔒 隐私优先    不暴露对方位置，仅用于天气查询
🎯 简洁温暖    暖珊瑚色主色调，Material 3 圆润风格
📱 单机优先    无服务器依赖，所有数据本地 SQLite
```

---

## 🏗️ 技术架构

采用**纯客户端单机架构**，所有数据存储在手机本地的 SQLite 中，无需任何服务器。AI 和天气服务由手机直连外部 API。

### 技术栈

| 层面 | 选型 | 说明 |
|------|------|------|
| 📱 **框架** | Flutter 3.41.9 + Dart | 跨平台，Material 3 温暖风格 |
| 🧭 **路由** | GoRouter | 声明式路由 + 认证重定向 |
| 🗄️ **本地数据库** | SQLite (sqflite) | 全部数据本地存储，无需服务器 |
| 🤖 **AI 服务** | DeepSeek API | 用户自行配置 API Key，直连手机 |
| 🌦️ **天气 API** | wttr.in | 免费开源，无需 Key |
| 🔔 **本地通知** | flutter_local_notifications | zonedSchedule 精确调度 |
| ⚙️ **后台任务** | WorkManager | 周期任务保活 |
| 📍 **定位** | geolocator + permission_handler | GPS + 权限管理 |
| ✨ **动画** | flutter_animate | 入场淡入、弹性效果 |
| 🌐 **网络** | Dio | HTTP 请求（天气/AI） |
| 🎨 **UI** | Material 3 + 自定义设计系统 | 暖珊瑚色主色，8px 基线网格 |

### 架构示意

```
┌──────────────────────────────────────────────────────────┐
│                   📱 Flutter APP (Android)                │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  presentation│  │   services   │  │     data      │  │
│  │   (UI 层)    │──│  (服务层)    │──│   (数据层)    │  │
│  │  screens/    │  │  ai_service  │  │  models/      │  │
│  │  widgets/    │  │  weather_svc │  │  SQLite DB    │  │
│  └──────────────┘  │  notif_svc   │  │  city_data    │  │
│                     │  reminder_   │  └───────────────┘  │
│                     │  scheduler   │                     │
│                     └──────┬───────┘                     │
└────────────────────────────┼─────────────────────────────┘
                             │ HTTPS (直连)
                    ┌────────┴────────┐
                    ▼                 ▼
              ┌──────────┐     ┌───────────┐
              │ 🤖 DeepSeek│    │ 🌦 wttr.in │
              │   AI API  │    │  天气 API  │
              └──────────┘     └───────────┘
```

---

## 📁 项目结构

```
TaWorld/
├── app/                               # Flutter 移动端
│   ├── lib/
│   │   ├── main.dart                  # 入口
│   │   ├── app/                       # 应用级配置
│   │   │   ├── app.dart               # MaterialApp 根组件
│   │   │   ├── router.dart            # GoRouter 路由表
│   │   │   ├── theme.dart             # 主题（亮色+暗色）
│   │   │   ├── design_tokens.dart     # 设计令牌
│   │   │   └── typography.dart        # 字体配置
│   │   ├── data/                      # 数据层
│   │   │   ├── models/                # 数据模型
│   │   │   │   ├── user.dart          # 用户
│   │   │   │   ├── partner.dart       # 关心的人
│   │   │   │   ├── reminder_config.dart # 提醒配置
│   │   │   │   ├── reminder_log.dart  # 提醒日志
│   │   │   │   └── achievement.dart   # 成就
│   │   │   ├── city_data.dart         # 世界城市数据（24国300+城）
│   │   │   └── local/database_helper.dart # SQLite 数据库管理
│   │   ├── services/                  # 服务层
│   │   │   ├── ai_service.dart        # DeepSeek AI 对话 + Key管理
│   │   │   ├── weather_service.dart   # wttr.in 天气查询
│   │   │   ├── notification_service.dart # 本地通知
│   │   │   ├── reminder_scheduler.dart # 提醒调度器
│   │   │   ├── background_tasks.dart  # WorkManager 后台任务
│   │   │   ├── care_suggestion_service.dart # 关怀建议
│   │   │   ├── theme_service.dart     # 主题切换
│   │   │   └── local/                 # 本地数据服务
│   │   │       ├── local_user_service.dart
│   │   │       ├── partner_service.dart
│   │   │       ├── local_reminder_service.dart
│   │   │       └── local_achievement_service.dart
│   │   └── presentation/              # UI 层
│   │       ├── screens/
│   │       │   ├── ai_home/           # AI 主屏（Tab 1）
│   │       │   ├── home/              # 首页容器 + 关心的人（Tab 2）+ 我的（Tab 3）
│   │       │   ├── add_partner/       # 添加关心的人
│   │       │   ├── partner_detail/    # 关心的人详情/编辑
│   │       │   ├── reminder_config/   # 提醒配置
│   │       │   ├── reminder_history/  # 提醒历史
│   │       │   ├── achievements/      # 成就列表
│   │       │   ├── ai_chat/           # AI 对话（旧版）
│   │       │   ├── api_key_setup/     # API Key 管理
│   │       │   ├── onboarding/        # 引导页
│   │       │   └── settings/          # 设置
│   │       └── widgets/               # 组件库
│   │           ├── widgets.dart       # 统一导出
│   │           ├── city_picker_sheet.dart # 城市选择器
│   │           ├── ta_card.dart / ta_button.dart / ta_text_field.dart
│   │           ├── ta_avatar.dart / ta_loading.dart
│   │           └── ta_achievement_badge.dart
│   └── pubspec.yaml
│
├── server/                            # ⚠️ [已废弃] Python 后端（保留仅供历史参考）
│
├── docs/                              # 项目文档
│   ├── architecture.md                # 旧架构方案（历史参考）
│   ├── design_system.md               # 前端设计系统规范 ✅ 当前有效
│   ├── frontend_guide.md              # 前端开发指南 ✅ 当前有效
│   ├── developer_guide.md             # 后端开发指引（历史参考）
│   ├── walkthrough.md                 # 后端验收报告（历史参考）
│   └── standalone_refactor_plan.md    # 单机版重构方案
│
└── .gitignore
```

> ⚠️ **注意**：`server/` 目录下的 Python 后端代码已废弃，项目已从服务端架构重构为纯单机 Flutter APP。该目录保留仅供历史参考，请勿在新开发中使用。

---

## 🧭 导航结构

APP 采用底部 **3-Tab 导航**：

| Tab | 页面 | 说明 |
|-----|------|------|
| 1 | **AI 助手** (AiHomeScreen) | AI 对话 + 主动消息 + 快捷芯片 |
| 2 | **关心的人** (_PartnersTab) | 可展开卡片列表，显示城市/时间/天气 |
| 3 | **我的** (_ProfileTab) | 头像/统计/菜单 |

### 路由表

| 路径 | 页面 |
|------|------|
| `/` | 首页（底部导航 3 Tab） |
| `/onboarding` | 引导页 |
| `/partners/add` | 添加关心的人 |
| `/partners/:id` | 关心的人详情/编辑 |
| `/reminders/config/:partnerId` | 提醒配置 |
| `/reminders/:id/logs` | 提醒历史 |
| `/achievements` | 成就列表 |
| `/ai/chat` | AI 对话（旧版） |
| `/settings/api-keys` | API Key 管理 |
| `/settings` | 设置 |

---

## 🚀 快速开始

### 前置条件

- Flutter 3.41.9+
- Android 设备或模拟器（iOS 可扩展）

### 运行

```bash
# 1. 进入 app 目录
cd app

# 2. 安装依赖
flutter pub get

# 3. 连接安卓设备或启动模拟器，然后运行
flutter run

# 4. 打 release 包
flutter build apk --release
```

就这么简单，没有服务器要启动，没有数据库要配置，没有 Docker 要编排 😊

---

## 🔒 隐私说明

TaWorld 是一款**完全离线**的 APP：

- 📱 **所有数据存储在设备本地** SQLite 中，没有服务器，没有云端同步
- 🤖 **AI API Key（DeepSeek）** 由用户自行配置，手机直连 DeepSeek 服务器
- 🌦️ **天气查询** 直连 wttr.in，不经过任何中间服务器
- 🚫 **没有中间服务器** —— 不收集用户数据，不做数据上报
- 📍 **位置信息** 仅用于天气查询，不暴露给对方

你的关心，只留在你的手机里。

---

## 💡 设计理念

| 理念 | 说明 |
|------|------|
| 🫶 **人是桥梁** | APP 不直接提醒 B，而是提醒 A 去关心 B。关怀的主体永远是人，不是机器 |
| 🔒 **隐私优先** | 不暴露对方位置，位置仅用于天气查询。所有数据本地存储 |
| 🎯 **简洁温暖** | 暖珊瑚色主色调，Material 3 圆润风格，8px 基线网格，让 APP 看起来像一个温暖的朋友 |
| 📱 **单机优先** | 无服务器依赖，无需注册账号，打开就能用。降低使用门槛，保护用户隐私 |

---

## 📖 文档索引

### 当前有效文档

| 文档 | 说明 |
|------|------|
| [前端设计系统规范](docs/design_system.md) | ✅ 设计令牌、色彩、字体、组件规范 |
| [前端开发指南](docs/frontend_guide.md) | ✅ Flutter 开发规范、组件开发、状态管理 |
| [单机版重构方案](docs/standalone_refactor_plan.md) | 从服务端架构到单机架构的重构记录 |

### 历史参考文档

> 以下文档描述的是旧的 Python 服务端架构，已不再使用，仅供历史参考。

| 文档 | 说明 |
|------|------|
| [技术架构方案](docs/architecture.md) | 旧架构设计文档（FastAPI + PostgreSQL + Redis） |
| [后端开发指引](docs/developer_guide.md) | 旧后端模块规范、代码模式 |
| [后端验收报告](docs/walkthrough.md) | 旧后端验收文档 |

---

## 🤝 参与开发

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交变更 (`git commit -m 'feat: add amazing feature'`)
4. 推送分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

---

<p align="center">
  Made with ❤️ by TaWorld Team
</p>
