# TaWorld 后端开发指引

> **本文档面向所有参与开发的 AI 模型和开发者。**
> 在开始任何编码之前，请先完整阅读本文档和 [architecture.md](architecture.md)。

---

## 一、项目现状

后端全部功能已开发完成并通过验收（33/33 测试通过）。Flutter 前端设计系统已建好，等待页面填充。

| 指标 | 数据 |
|------|------|
| 后端文件总数 | 80+ 个 |
| API 路由 | 36 个（30 业务 + 6 系统） |
| 数据库表 | 8 张（与 architecture.md ER 图一致） |
| 业务模块 | 7 个（auth/users/relationships/reminders/weather/achievements/ai） |
| 测试用例 | 33 个（全部通过） |
| Flutter 前端 | 设计系统 + 组件库 + 2 个参考页面（登录/首页） |

---

## 二、项目结构总览

```
TaWorld/
├── .gitignore
├── README.md
├── CLAUDE.md                      # AI 开发者上下文指引
├── docker-compose.yml             # Docker 编排（API + PG + Redis + MinIO）
├── docs/
│   ├── architecture.md            # 完整技术架构方案（必读）
│   ├── architecture_comparison.md # 架构 vs 实现对比报告
│   ├── developer_guide.md         # 本文档（后端开发指引）
│   ├── frontend_guide.md          # 前端开发指引
│   ├── design_system.md           # 前端设计系统规范
│   └── walkthrough.md             # 后端验收报告
│
├── app/                           # ★ Flutter 移动端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                   #   主题/路由/设计令牌
│   │   ├── core/                  #   网络层/常量
│   │   ├── services/              #   认证服务
│   │   └── presentation/
│   │       ├── screens/           #   页面
│   │       └── widgets/           #   组件库（TaCard/TaButton/...）
│   └── pubspec.yaml
│
└── server/                        # ★ Python 后端
    ├── .env.example               # 环境变量模板
    ├── Dockerfile
    ├── requirements.txt
    ├── alembic.ini
    ├── alembic/
    │   ├── env.py
    │   └── versions/
    │       └── 0001_initial_tables.py  # 手写初始迁移
    ├── tests/
    │   ├── conftest.py            # 测试 Fixtures
    │   ├── test_auth.py
    │   ├── test_achievements.py
    │   ├── test_relationships.py
    │   ├── test_reminders.py
    │   ├── test_push.py
    │   ├── test_storage.py
    │   └── test_system.py
    └── app/
        ├── main.py                # FastAPI 入口
        ├── core/
        │   ├── config.py          #   Settings
        │   ├── database.py        #   Engine + Session + Mixins
        │   ├── security.py        #   JWT + bcrypt
        │   ├── dependencies.py    #   认证依赖 + Redis
        │   ├── push_service.py    #   FCM 推送（优雅降级）
        │   └── storage.py         #   MinIO 头像上传
        ├── common/
        │   ├── response.py        #   统一响应
        │   ├── exceptions.py      #   异常体系
        │   ├── pagination.py      #   分页
        │   └── rate_limit.py      #   滑动窗口限流
        ├── modules/               # 7 个业务模块
        │   ├── auth/
        │   ├── users/
        │   ├── relationships/
        │   ├── reminders/
        │   ├── weather/
        │   ├── achievements/
        │   └── ai/
        └── tasks/
            ├── scheduler.py
            ├── weather_check.py
            └── reminder_trigger.py
```

---

## 三、模块开发规范（重要）

### 3.1 每个模块的标准结构

```
modules/{module_name}/
├── __init__.py     # 模块标识
├── models.py       # SQLAlchemy ORM 模型（数据库表定义）
├── schemas.py      # Pydantic 数据验证模型（API 请求/响应）
├── service.py      # 业务逻辑（纯逻辑，不依赖 HTTP 层）
└── router.py       # FastAPI 路由（接收请求，调用 service）
```

### 3.2 调用链（严格遵守）

```
router.py → service.py → models.py
   ↑ HTTP       ↑ 逻辑       ↑ 数据库
```

**禁止**：在 router.py 中直接操作数据库（写 SQL 查询）。所有逻辑必须通过 service 层。

### 3.3 新增功能的标准流程

1. 在对应的 `modules/{name}/` 下修改文件
2. 按 `models → schemas → service → router` 的**依赖顺序**开发
3. 如果修改了 models，运行 `alembic revision --autogenerate -m "描述"` 生成迁移

### 3.4 新增模块的标准流程

1. 在 `server/app/modules/` 下创建新目录，包含上述 5 个文件
2. 在 `app/main.py` 的 `_register_routers()` 函数中添加路由注册
3. 如果有新的数据库模型，在 `alembic/env.py` 中添加 `from app.modules.xxx.models import *`
4. 运行 `alembic revision --autogenerate` 生成迁移

---

## 四、关键代码模式（复制即用）

### 4.1 统一响应格式

所有 API 必须使用统一响应，格式为 `{"code": 0, "message": "success", "data": {...}}`。

```python
from app.common.response import success_response, error_response, paginated_response

# 成功响应
return success_response(data={"id": "xxx"}, message="操作成功")

# 分页响应
return paginated_response(items=[...], total=100, page=1, page_size=20)
```

### 4.2 异常处理

使用自定义异常类，**不要**直接 raise HTTPException。

```python
from app.common.exceptions import AuthException, UserException, RelationshipException, ReminderException, SystemException

# 示例
raise AuthException(
    code=AuthException.INVALID_CREDENTIALS,  # 1001
    message="手机号或密码错误",
)

raise RelationshipException(
    code=RelationshipException.INVITE_INVALID,  # 3004
    message="邀请码无效",
    status_code=404,
)
```

错误码范围：
- `1xxx` — 认证（AuthException）
- `2xxx` — 用户（UserException）
- `3xxx` — 关系（RelationshipException）
- `4xxx` — 提醒（ReminderException）
- `5xxx` — 系统（SystemException）

### 4.3 路由需要认证

```python
from typing import Annotated
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.modules.users.models import User

router = APIRouter(prefix="/xxx", tags=["模块名"])

@router.get("/example", summary="接口说明")
async def example(
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """接口文档"""
    # current_user 就是当前登录的用户对象
    # db 就是数据库 Session
    pass
```

### 4.4 数据库模型（使用 Mixin）

```python
from app.core.database import Base, UUIDMixin, TimestampMixin

class MyModel(Base, UUIDMixin, TimestampMixin):
    """
    UUIDMixin 提供: id (UUID 主键, 自动生成)
    TimestampMixin 提供: created_at, updated_at (自动维护)
    """
    __tablename__ = "my_table"
    
    name: Mapped[str] = mapped_column(String(100), nullable=False)
```

### 4.5 分页查询

```python
from fastapi import Depends
from app.common.pagination import PaginationParams, get_pagination, paginate
from app.common.response import paginated_response

@router.get("/list")
async def list_items(
    db: Annotated[AsyncSession, Depends(get_db)],
    pagination: PaginationParams = Depends(get_pagination),
):
    query = select(MyModel).order_by(MyModel.created_at.desc())
    items, total = await paginate(db, query, pagination)
    return paginated_response(
        items=[ItemResponse.model_validate(i).model_dump(mode="json") for i in items],
        total=total,
        page=pagination.page,
        page_size=pagination.page_size,
    )
```

### 4.6 Redis 缓存

```python
import redis.asyncio as aioredis
from app.core.dependencies import get_redis

@router.get("/cached")
async def cached_endpoint(
    redis_client: Annotated[aioredis.Redis, Depends(get_redis)],
):
    # 读取缓存
    cached = await redis_client.get("my_key")
    if cached:
        return success_response(data=json.loads(cached))
    
    # 写入缓存（TTL 30 分钟）
    await redis_client.setex("my_key", 1800, json.dumps(data))
```

---

## 五、API 路由完整对照表

全部 30 个业务路由 + 6 个系统路由 = **36 个路由**。

| 模块 | 方法 | 路径 | 说明 |
|------|------|------|------|
| **认证** | POST | `/api/v1/auth/register` | 手机号注册 |
| | POST | `/api/v1/auth/login` | 登录获取 Token |
| | POST | `/api/v1/auth/refresh` | 刷新 Token |
| **用户** | GET | `/api/v1/users/me` | 获取当前用户信息 |
| | PUT | `/api/v1/users/me` | 更新用户信息 |
| | PUT | `/api/v1/users/me/location` | 上报位置 |
| | POST | `/api/v1/users/me/devices` | 注册推送设备 |
| | GET | `/api/v1/users/me/stats` | 用户概览统计 |
| | POST | `/api/v1/users/me/avatar` | 头像上传 |
| | DELETE | `/api/v1/users/me/avatar` | 头像删除 |
| | GET | `/api/v1/users/me/achievements` | 我的成就进度 |
| **关系** | POST | `/api/v1/relationships/invite` | 生成邀请码 |
| | POST | `/api/v1/relationships/join` | 通过邀请码加入 |
| | GET | `/api/v1/relationships` | 我的所有关系 |
| | GET | `/api/v1/relationships/{id}` | 关系详情 |
| | PUT | `/api/v1/relationships/{id}` | 更新关系 |
| | DELETE | `/api/v1/relationships/{id}` | 解除关系 |
| **提醒** | GET | `/api/v1/relationships/{id}/reminders` | 获取提醒配置 |
| | POST | `/api/v1/relationships/{id}/reminders` | 创建提醒配置 |
| | PUT | `/api/v1/reminders/{id}` | 更新提醒配置 |
| | DELETE | `/api/v1/reminders/{id}` | 删除提醒配置 |
| | POST | `/api/v1/reminders/{id}/send` | 一键提醒（A→B） |
| | POST | `/api/v1/reminders/{id}/confirm` | 确认收到（B 确认） |
| | GET | `/api/v1/reminders/{id}/logs` | 提醒历史 |
| | GET | `/api/v1/reminders/stats` | 提醒统计数据 |
| **天气** | GET | `/api/v1/weather/current` | 查询天气（调试用） |
| **成就** | GET | `/api/v1/achievements` | 所有成就列表 |
| **AI** | POST | `/api/v1/ai/suggest` | AI 生成关怀建议 |
| | POST | `/api/v1/ai/chat` | AI 对话交互 |
| **系统** | GET | `/` | 欢迎页 |
| | GET | `/health` | 健康检查 |
| | GET | `/api/v1/config` | 客户端启动配置 |

---

## 六、数据库表

共 8 张表，与 architecture.md 中的 ER 图完全对应：

| 表名 | ORM 模型 | 文件位置 | 说明 |
|------|---------|---------|------|
| `users` | User | `modules/users/models.py` | 用户信息 |
| `user_locations` | UserLocation | `modules/users/models.py` | 用户位置（一对一） |
| `devices` | Device | `modules/users/models.py` | 推送设备（FCM Token） |
| `relationships` | Relationship | `modules/relationships/models.py` | 一对一关系 |
| `reminder_configs` | ReminderConfig | `modules/reminders/models.py` | 提醒配置（含 JSONB） |
| `reminder_logs` | ReminderLog | `modules/reminders/models.py` | 提醒日志 |
| `achievements` | Achievement | `modules/achievements/models.py` | 成就定义（含种子数据） |
| `user_achievements` | UserAchievement | `modules/achievements/models.py` | 用户成就进度 |

---

## 七、开发环境启动

```bash
# 1. 启动 PostgreSQL + Redis（使用 Docker）
docker-compose up -d postgres redis

# 2. 进入 server 目录
cd server

# 3. 激活虚拟环境
venv\Scripts\activate          # Windows
# source venv/bin/activate     # Linux/Mac

# 4. 复制环境变量（首次需要）
copy .env.example .env
# 编辑 .env，至少填写 JWT_SECRET_KEY

# 5. 生成并执行初始数据库迁移
alembic revision --autogenerate -m "initial tables"
alembic upgrade head

# 6. 启动开发服务器
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 7. 访问 API 文档
# http://localhost:8000/docs
```

---

## 八、当前开发状态

骨架代码中的 `# TODO` 已全部清除。以下为各模块实现状态：

| 模块 | 状态 | 说明 |
|------|------|------|
| FCM 推送 | ✅ 完成 | PushService 已集成到 send_reminder / confirm_reminder / weather_check / reminder_trigger，未配置 Key 时优雅降级 |
| 成就解锁 | ✅ 完成 | 支持 4 种类型：count / streak_days / mutual_reminder_count / relationship_days |
| 天气服务 | ✅ 完成 | API Key 验证、详细错误日志、WeatherCheckResult.error 字段 |
| AI 服务 | ✅ 完成 | LLM 未配置时直接降级到预设模板，JSON 解析容错 |
| 频率限制 | ✅ 完成 | 认证接口 10req/60s，localhost 豁免 |
| 头像上传 | ✅ 完成 | MinIO 存储，POST/DELETE /users/me/avatar |
| 提醒统计 | ✅ 完成 | GET /reminders/stats 和 GET /users/me/stats |
| 客户端配置 | ✅ 完成 | GET /api/v1/config 返回功能开关和 UI 常量 |

### 下一步开发

1. **配置 API Key** — 在 `.env` 中填入 QWEATHER_API_KEY / LLM_API_KEY / FCM_SERVER_KEY
2. **Flutter 前端页面填充** — 设计系统和组件库已建好，参考 `docs/frontend_guide.md` 实现剩余页面
3. **启动 MinIO** — `docker-compose up -d minio` 激活头像上传功能
4. **前后端联调** — 后端在 `localhost:8000` 运行，Flutter 用 `http://10.0.2.2:8000` 连接

---

## 九、代码规范

| 规则 | 说明 |
|------|------|
| 语言 | 中文注释，英文代码 |
| Python 风格 | PEP 8, 使用 type hints, 所有函数写 docstring |
| 命名 | `snake_case`(变量/函数), `PascalCase`(类), `UPPER_SNAKE`(常量) |
| 响应格式 | 统一使用 `success_response()` / `error_response()` |
| 异常处理 | 使用 `common/exceptions.py` 中的异常类 |
| 认证 | 需要登录的接口添加 `Depends(get_current_active_user)` |
| Git Commit | `feat:` / `fix:` / `docs:` / `refactor:` / `chore:` |

---

> 此文档应随项目迭代同步更新。当新增模块或变更架构时，请更新对应章节。
