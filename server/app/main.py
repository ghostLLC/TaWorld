"""
TaWorld — FastAPI 应用入口

创建 FastAPI 实例，注册路由、中间件、事件处理器。
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.common.exceptions import register_exception_handlers
from app.core.config import get_settings
from app.core.database import close_db, init_db
from app.core.dependencies import close_redis, init_redis

settings = get_settings()

# 日志配置
logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理"""
    # ===== 启动 =====
    logger.info(f"🚀 {settings.APP_NAME} v{settings.APP_VERSION} 正在启动...")

    # 初始化数据库连接
    await init_db()
    logger.info("✅ 数据库连接已建立")

    # 初始化 Redis
    try:
        await init_redis()
        logger.info("✅ Redis 连接已建立")
    except Exception as e:
        logger.warning(f"⚠️ Redis 连接失败（非致命）: {e}")

    # 初始化定时任务调度器
    try:
        from app.tasks.scheduler import init_scheduler
        init_scheduler()
    except Exception as e:
        logger.warning(f"⚠️ 定时任务调度器启动失败（非致命）: {e}")

    # 初始化成就种子数据
    try:
        from app.core.database import async_session_factory
        from app.modules.achievements.service import AchievementService
        async with async_session_factory() as db:
            await AchievementService.seed_achievements(db)
            await db.commit()
        logger.info("✅ 成就种子数据已初始化")
    except Exception as e:
        logger.warning(f"⚠️ 成就种子数据初始化失败（非致命）: {e}")

    logger.info(f"🎉 {settings.APP_NAME} 启动成功！")
    logger.info(f"📖 API 文档: http://localhost:8000/docs")

    yield

    # ===== 关闭 =====
    logger.info(f"🛑 {settings.APP_NAME} 正在关闭...")

    # 关闭定时任务调度器
    try:
        from app.tasks.scheduler import shutdown_scheduler
        shutdown_scheduler()
    except Exception:
        pass

    # 关闭 Redis
    await close_redis()

    # 关闭数据库
    await close_db()

    logger.info(f"👋 {settings.APP_NAME} 已关闭")


def create_app() -> FastAPI:
    """创建 FastAPI 应用实例"""

    app = FastAPI(
        title=settings.APP_NAME,
        description="一款以「关怀」为核心的情感连接APP后端服务",
        version=settings.APP_VERSION,
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    # ==================== 中间件 ====================

    # 频率限制（认证接口）
    from app.common.rate_limit import RateLimitMiddleware
    app.add_middleware(RateLimitMiddleware)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # 开发阶段允许所有来源，生产环境需限制
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ==================== 异常处理 ====================
    register_exception_handlers(app)

    # ==================== 注册路由 ====================
    _register_routers(app)

    return app


def _register_routers(app: FastAPI) -> None:
    """注册所有模块路由"""
    from app.modules.auth.router import router as auth_router
    from app.modules.users.router import router as users_router
    from app.modules.relationships.router import router as relationships_router
    from app.modules.reminders.router import router as reminders_router
    from app.modules.weather.router import router as weather_router
    from app.modules.achievements.router import router as achievements_router
    from app.modules.ai.router import router as ai_router

    prefix = settings.API_V1_PREFIX

    app.include_router(auth_router, prefix=prefix)
    app.include_router(users_router, prefix=prefix)
    app.include_router(relationships_router, prefix=prefix)
    app.include_router(reminders_router, prefix=prefix)
    app.include_router(weather_router, prefix=prefix)
    app.include_router(achievements_router, prefix=prefix)
    app.include_router(ai_router, prefix=prefix)

    logger.info(f"✅ 已注册 7 个模块路由（前缀: {prefix}）")


# 创建应用实例
app = create_app()


# ==================== 根路由（健康检查） ====================

@app.get("/", tags=["系统"])
async def root():
    """健康检查 & 欢迎页"""
    return {
        "code": 0,
        "message": f"Welcome to {settings.APP_NAME}! 🫶",
        "data": {
            "name": settings.APP_NAME,
            "version": settings.APP_VERSION,
            "docs": "/docs",
        },
    }


@app.get("/health", tags=["系统"])
async def health_check():
    """健康检查接口"""
    return {"status": "ok"}


@app.get("/api/v1/config", tags=["系统"])
async def app_config():
    """客户端配置接口 — 返回Flutter App需要的启动配置"""
    settings = get_settings()
    return {
        "code": 0,
        "message": "success",
        "data": {
            "app_name": settings.APP_NAME,
            "version": settings.APP_VERSION,
            "features": {
                "ai_chat": bool(settings.LLM_API_KEY),
                "weather_reminder": bool(settings.QWEATHER_API_KEY),
                "push_notifications": bool(settings.FCM_SERVER_KEY),
            },
            "reminder_categories": [
                {"key": "weather", "label": "天气提醒", "icon": "🌦️"},
                {"key": "sleep", "label": "睡觉提醒", "icon": "🌙"},
                {"key": "meal", "label": "吃饭提醒", "icon": "🍚"},
                {"key": "custom", "label": "自定义提醒", "icon": "💝"},
            ],
            "relationship_types": [
                {"key": "couple", "label": "情侣", "icon": "💑"},
                {"key": "family", "label": "家人", "icon": "👨‍👩‍👧"},
                {"key": "friend", "label": "朋友", "icon": "🤝"},
            ],
        },
    }
