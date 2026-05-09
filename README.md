# 🫶 Ta的世界（TaWorld）

<p align="center">
  <strong>一款以「关怀」为核心的情感连接 APP</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/python-3.12-blue?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white" alt="FastAPI">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white" alt="PostgreSQL">
  <img src="https://img.shields.io/badge/Redis-7-DC382D?logo=redis&logoColor=white" alt="Redis">
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" alt="Docker">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

> 用户通过建立一对一关系，在天气变化、作息时间等场景下，**由 APP 提醒用户 A 去主动关心用户 B**，保留人与人之间的温度。

## ✨ 核心功能

| 功能 | 说明 | 状态 |
|------|------|------|
| 🌦️ **天气提醒** | 对方所在地天气变化时，提醒你去关心 Ta | ✅ 已完成 |
| 🌙 **作息提醒** | 到了睡觉/吃饭时间，提醒你关心 Ta | ✅ 已完成 |
| 🔗 **关系管理** | 通过邀请码建立一对一关系（情侣/家人/朋友） | ✅ 已完成 |
| 🏆 **成就系统** | 记录每一次关怀，解锁温暖成就徽章 | ✅ 已完成 |
| 🤖 **AI 助手** | 智能生成关怀语，让每次关心更有温度 | ✅ 已完成 |
| 📲 **推送通知** | FCM 推送，提醒及时到达 | ✅ 已完成 |
| 🖼️ **头像上传** | MinIO 对象存储，支持 JPEG/PNG/WebP | ✅ 已完成 |
| 📊 **数据统计** | 提醒总数、连续天数、分类汇总 | ✅ 已完成 |

### 核心设计理念

```
🫶 人是桥梁    APP 不直接提醒 B，而是提醒 A 去关心 B
🔒 隐私优先    不暴露对方位置，仅用于天气查询
🎯 简洁温暖    交互极简，体验温暖
📈 可扩展      模块化设计，支持自定义提醒和 AI 扩展
```

---

## 🏗️ 技术架构

采用 **模块化单体（Modular Monolith）** 架构，每个模块有独立的 `routes / services / models`，未来可按需拆分为微服务。

### 技术栈

| 层面 | 选型 | 说明 |
|------|------|------|
| 📱 **移动端** | Flutter 3.x + Riverpod + GoRouter | 单代码库跨平台（Android → iOS） |
| 🖥️ **后端框架** | Python 3.12 + FastAPI | 异步高性能，自动 API 文档 |
| 🗄️ **数据库** | PostgreSQL 16 + SQLAlchemy 2.0 | 关系型数据 + JSONB 灵活配置 |
| ⚡ **缓存/队列** | Redis 7 | 天气缓存、会话管理 |
| 🔐 **认证** | JWT (Access + Refresh Token) | 无状态认证，移动端友好 |
| ⏰ **任务调度** | APScheduler | 天气检查（每小时）、定时提醒（每分钟） |
| 🌦️ **天气 API** | 和风天气 (QWeather) | 中国区域覆盖好 |
| 🤖 **AI 服务** | OpenAI / 通义千问 | 关怀语生成、对话交互 |
| 🐳 **部署** | Docker + Docker Compose | 一键启动全部服务 |

### 系统架构图

```
┌──────────────────────────────────────────────────────┐
│                📱 Flutter APP (Android)               │
│        UI Layer → Business Logic → Data Layer         │
└────────────────────┬─────────────────────────────────┘
                     │ HTTPS / REST
┌────────────────────▼─────────────────────────────────┐
│               🖥️ FastAPI Backend                      │
│                                                       │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌───────────┐ │
│  │  Auth   │ │  Users  │ │Relations │ │ Reminders │ │
│  └─────────┘ └─────────┘ └──────────┘ └───────────┘ │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐               │
│  │ Weather │ │  Achiev │ │    AI    │               │
│  └─────────┘ └─────────┘ └──────────┘               │
│                                                       │
│  ┌──────────────────────────────────┐                │
│  │   ⏰ Task Scheduler (APScheduler)│                │
│  └──────────────────────────────────┘                │
└──┬───────────┬───────────┬───────────────────────────┘
   │           │           │
   ▼           ▼           ▼
┌──────┐  ┌────────┐  ┌────────────────────────┐
│ 🐘   │  │ ⚡     │  │  🌐 External Services  │
│Postgr│  │ Redis  │  │  • FCM Push            │
│ eSQL │  │        │  │  • QWeather API        │
│      │  │        │  │  • LLM API             │
└──────┘  └────────┘  └────────────────────────┘
```

---

## 📁 项目结构

```
TaWorld/
├── .gitignore
├── README.md                      ← 你在这里
├── docker-compose.yml             # Docker 编排（API + PG + Redis）
├── docs/
│   └── architecture.md            # 完整技术架构方案文档
│
└── server/                        # ========== Python 后端 ==========
    ├── .env.example               # 环境变量模板
    ├── Dockerfile                 # 容器构建文件
    ├── requirements.txt           # Python 依赖（锁定版本）
    ├── alembic.ini                # Alembic 数据库迁移配置
    │
    ├── alembic/                   # 数据库迁移
    │   ├── env.py                 # 异步迁移环境
    │   ├── script.py.mako         # 迁移脚本模板
    │   └── versions/              # 迁移版本文件
    │
    ├── tests/                     # 单元测试
    │   ├── conftest.py            # 测试 Fixtures
    │   ├── test_auth.py           # 认证测试
    │   └── test_system.py         # 系统接口测试
    │
    └── app/                       # 应用主目录
        ├── main.py                # ★ FastAPI 入口 + 生命周期
        │
        ├── core/                  # 🔧 核心基础层
        │   ├── config.py          #   环境配置 (pydantic-settings)
        │   ├── database.py        #   异步数据库引擎 + ORM Base
        │   ├── security.py        #   密码哈希 + JWT Token
        │   └── dependencies.py    #   认证依赖 + Redis 依赖
        │
        ├── common/                # 🛠️ 公共工具层
        │   ├── response.py        #   统一响应格式 {code, message, data}
        │   ├── exceptions.py      #   异常体系 (1xxx~5xxx 错误码)
        │   └── pagination.py      #   分页参数 + 分页查询工具
        │
        ├── modules/               # 📦 业务模块（模块化单体）
        │   ├── auth/              #   🔐 认证：注册/登录/Token刷新
        │   │   ├── schemas.py     #      请求/响应数据模型
        │   │   ├── service.py     #      业务逻辑
        │   │   └── router.py      #      API 路由
        │   ├── users/             #   👤 用户：信息/位置/设备
        │   │   ├── models.py      #      User + UserLocation + Device
        │   │   ├── schemas.py
        │   │   ├── service.py
        │   │   └── router.py
        │   ├── relationships/     #   🔗 关系：邀请/加入/管理
        │   │   ├── models.py      #      Relationship (含状态机)
        │   │   ├── schemas.py
        │   │   ├── service.py
        │   │   └── router.py
        │   ├── reminders/         #   🔔 提醒：配置/发送/确认/日志
        │   │   ├── models.py      #      ReminderConfig + ReminderLog
        │   │   ├── schemas.py
        │   │   ├── service.py
        │   │   └── router.py
        │   ├── weather/           #   🌦️ 天气：查询/缓存/条件判断
        │   │   ├── schemas.py
        │   │   ├── service.py     #      和风天气 API 集成
        │   │   └── router.py
        │   ├── achievements/      #   🏆 成就：定义/进度/解锁
        │   │   ├── models.py      #      Achievement + UserAchievement
        │   │   ├── schemas.py
        │   │   ├── service.py     #      含 7 个预设成就种子数据
        │   │   └── router.py
        │   └── ai/                #   🤖 AI：建议/对话
        │       ├── schemas.py
        │       ├── service.py     #      LLM API + Prompt 模板 + 降级方案
        │       └── router.py
        │
        └── tasks/                 # ⏰ 定时任务
            ├── scheduler.py       #   APScheduler 初始化
            ├── weather_check.py   #   天气检查（每小时）
            └── reminder_trigger.py #  定时提醒触发（每分钟）
```

### 模块统一结构

每个业务模块遵循 **4 层结构**，调用链从右到左：

```
models.py ← schemas.py ← service.py ← router.py
(数据库表)   (数据验证)    (业务逻辑)    (API路由)
```

---

## 🚀 快速开始

### 前置条件

- Python 3.12+
- PostgreSQL 16+（或使用 Docker）
- Redis 7+（或使用 Docker）

### 方式一：Docker 一键部署（推荐）

```bash
# 1. 克隆项目
git clone <repo-url> TaWorld
cd TaWorld

# 2. 配置环境变量
copy server\.env.example server\.env
# 编辑 server/.env，填入实际配置（JWT密钥、API Key 等）

# 3. 一键启动所有服务
docker-compose up -d

# 4. 查看服务状态
docker-compose ps

# 5. 查看 API 日志
docker-compose logs -f api
```

### 方式二：本地开发

```bash
# ===== 1. 启动基础服务（数据库 + 缓存）=====
docker-compose up -d postgres redis

# ===== 2. 配置后端 =====
cd server

# 创建虚拟环境
python -m venv venv
venv\Scripts\activate          # Windows
# source venv/bin/activate     # Linux / Mac

# 安装依赖
pip install -r requirements.txt

# 配置环境变量
copy .env.example .env
# 编辑 .env 填入实际配置

# ===== 3. 初始化数据库 =====
alembic revision --autogenerate -m "initial tables"
alembic upgrade head

# ===== 4. 启动开发服务器 =====
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 访问 API 文档

启动服务后：

| 地址 | 说明 |
|------|------|
| http://localhost:8000 | 欢迎页 / 健康检查 |
| http://localhost:8000/docs | Swagger UI（交互式文档） |
| http://localhost:8000/redoc | ReDoc（阅读式文档） |
| http://localhost:8000/health | 健康检查端点 |

---

## 📡 API 概览

### 基础路径：`/api/v1`

<details>
<summary><strong>🔐 认证 (Auth)</strong></summary>

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/auth/register` | 手机号注册 |
| `POST` | `/auth/login` | 登录获取 Token |
| `POST` | `/auth/refresh` | 刷新 Token |

</details>

<details>
<summary><strong>👤 用户 (Users)</strong></summary>

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/users/me` | 获取当前用户信息 |
| `PUT` | `/users/me` | 更新用户信息 |
| `PUT` | `/users/me/location` | 上报位置 |
| `POST` | `/users/me/devices` | 注册推送设备 |

</details>

<details>
<summary><strong>🔗 关系 (Relationships)</strong></summary>

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/relationships/invite` | 生成邀请码 |
| `POST` | `/relationships/join` | 通过邀请码加入 |
| `GET` | `/relationships` | 获取我的所有关系 |
| `GET` | `/relationships/{id}` | 获取关系详情 |
| `PUT` | `/relationships/{id}` | 更新关系（备注名等） |
| `DELETE` | `/relationships/{id}` | 解除关系 |

</details>

<details>
<summary><strong>🔔 提醒 (Reminders)</strong></summary>

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/relationships/{id}/reminders` | 获取提醒配置列表 |
| `POST` | `/relationships/{id}/reminders` | 创建提醒配置 |
| `PUT` | `/reminders/{id}` | 更新提醒配置 |
| `DELETE` | `/reminders/{id}` | 删除提醒配置 |
| `POST` | `/reminders/{id}/send` | 一键提醒（A→B） |
| `POST` | `/reminders/{id}/confirm` | 确认收到（B 确认） |
| `GET` | `/reminders/{id}/logs` | 提醒历史记录 |

</details>

<details>
<summary><strong>🌦️ 天气 / 🏆 成就 / 🤖 AI</strong></summary>

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/weather/current` | 查询天气（调试用） |
| `GET` | `/achievements` | 所有成就列表 |
| `GET` | `/users/me/achievements` | 我的成就进度 |
| `POST` | `/ai/suggest` | AI 生成关怀建议 |
| `POST` | `/ai/chat` | AI 对话交互 |
| `POST` | `/users/me/avatar` | 上传头像 |
| `DELETE` | `/users/me/avatar` | 删除头像 |
| `GET` | `/users/me/stats` | 用户概览统计 |
| `GET` | `/reminders/stats` | 提醒统计数据 |
| `GET` | `/api/v1/config` | 客户端配置 |

</details>

### 统一响应格式

```json
{
  "code": 0,
  "message": "success",
  "data": { }
}
```

### 错误码体系

| 范围 | 模块 | 示例 |
|------|------|------|
| `1xxx` | 认证 | 1001 凭据无效, 1004 用户已存在 |
| `2xxx` | 用户 | 2001 用户不存在 |
| `3xxx` | 关系 | 3004 邀请码无效, 3005 不能邀请自己 |
| `4xxx` | 提醒 | 4001 配置不存在, 4004 已确认 |
| `5xxx` | 系统 | 5001 内部错误 |

---

## 🗄️ 数据库

### 表结构概览

共 **8 张表**：

| 表名 | 说明 | 关键字段 |
|------|------|---------|
| `users` | 用户信息 | phone, nickname, avatar_url, password_hash |
| `user_locations` | 用户位置（一对一） | latitude, longitude, city |
| `devices` | 推送设备 | fcm_token, device_info |
| `relationships` | 一对一关系 | user_a_id, user_b_id, type, status, invite_code |
| `reminder_configs` | 提醒配置 | category, enabled, config(JSONB) |
| `reminder_logs` | 提醒日志 | sender_id, receiver_id, status, message |
| `achievements` | 成就定义 | name, unlock_condition(JSONB), points |
| `user_achievements` | 用户成就进度 | progress, unlocked, unlocked_at |

### 数据库迁移

```bash
# 生成迁移（修改 models 后）
alembic revision --autogenerate -m "描述变更"

# 执行迁移
alembic upgrade head

# 回滚一步
alembic downgrade -1

# 查看迁移历史
alembic history
```

---

## 🧪 测试

```bash
cd server

# 运行所有测试（当前 33 个，覆盖 8 个测试文件）
pytest

# 运行指定测试文件
pytest tests/test_auth.py

# 运行指定测试方法
pytest tests/test_auth.py -k test_login

# 带覆盖率
pytest --cov=app
```

---

## 📝 开发规范

### 代码风格

| 语言 | 规范 |
|------|------|
| Python | PEP 8, type hints, 所有函数写 docstring |
| Dart/Flutter | Effective Dart, lint 规则 |
| 命名 | `snake_case`(Python), `camelCase`(Dart), `UPPER_SNAKE`(常量) |
| 注释 | 中文注释，英文代码 |

### Git 规范

```bash
# 分支
main              # 主分支（稳定版本）
develop            # 开发分支
feature/xxx        # 功能分支
bugfix/xxx         # 修复分支

# Commit Message
feat: 新功能
fix:  修复 Bug
docs: 文档变更
refactor: 重构
chore: 构建/工具变更
```

### 新增模块指南

1. 在 `server/app/modules/` 下创建新目录
2. 按 `models.py → schemas.py → service.py → router.py` 顺序开发
3. 在 `app/main.py` 的 `_register_routers()` 中注册路由
4. 如有新表，在 `alembic/env.py` 中导入 models
5. 运行 `alembic revision --autogenerate` 生成迁移

---

## 📋 开发路线图

### Phase 1 — MVP（4-6周）
- [x] 项目架构搭建
- [x] 用户注册/登录
- [x] 关系建立（邀请码机制）
- [x] 天气提醒（核心功能）
- [x] 一键提醒 + 确认机制
- [x] FCM 推送集成
- [x] 频率限制中间件
- [ ] 基础 UI（Flutter 前端）

### Phase 2 — 完善（3-4周）
- [x] 睡觉/吃饭提醒
- [x] 成就系统
- [x] AI 智能建议
- [x] 提醒历史/统计
- [x] 头像上传（MinIO）
- [ ] UI 打磨

### Phase 3 — 增强（3-4周）
- [x] 自定义提醒
- [ ] AI 行为分析
- [x] AI 对话交互
- [x] 客户端配置端点
- [ ] 性能优化

### Phase 4 — 扩展（待定）
- [ ] iOS 版本
- [ ] 应用商店上架
- [ ] 更多社交功能
- [ ] WebSocket 实时推送

---

## 📖 文档

| 文档 | 说明 |
|------|------|
| [技术架构方案](docs/architecture.md) | 完整技术设计文档，包含 ER 图、流程图、API 设计等 |
| [开发指引](docs/developer_guide.md) | **开发必读**：模块规范、代码模式、TODO 清单、开发顺序 |
| [Swagger UI](http://localhost:8000/docs) | 交互式 API 文档（需启动服务） |
| [ReDoc](http://localhost:8000/redoc) | 阅读式 API 文档（需启动服务） |

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
