"""
FastAPI 依赖注入模块

提供全局共用的依赖函数，如用户认证、Redis 连接等。
"""

import uuid
from typing import Annotated

import redis.asyncio as aioredis
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_db
from app.core.security import decode_token

settings = get_settings()

# OAuth2 密码模式（Token 来自 Header: Authorization: Bearer <token>）
oauth2_scheme = OAuth2PasswordBearer(
    tokenUrl=f"{settings.API_V1_PREFIX}/auth/login"
)

# Redis 连接池（应用启动时初始化）
_redis_pool: aioredis.Redis | None = None


async def init_redis() -> None:
    """初始化 Redis 连接池（应用启动时调用）"""
    global _redis_pool
    _redis_pool = aioredis.from_url(
        settings.REDIS_URL,
        encoding="utf-8",
        decode_responses=True,
    )


async def close_redis() -> None:
    """关闭 Redis 连接池（应用关闭时调用）"""
    global _redis_pool
    if _redis_pool:
        await _redis_pool.close()
        _redis_pool = None


async def get_redis() -> aioredis.Redis:
    """
    获取 Redis 连接

    Returns:
        Redis 异步连接实例

    Raises:
        HTTPException: Redis 未初始化
    """
    if _redis_pool is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Redis 服务不可用",
        )
    return _redis_pool


async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    从 JWT Token 中解析并返回当前用户

    Returns:
        当前认证用户的 User 模型实例

    Raises:
        HTTPException 401: Token 无效或用户不存在
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="无法验证凭据",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(token)
        user_id: str | None = payload.get("sub")
        token_type: str | None = payload.get("type")

        if user_id is None or token_type != "access":
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    # 延迟导入避免循环引用
    from app.modules.users.models import User

    result = await db.execute(
        select(User).where(User.id == uuid.UUID(user_id))
    )
    user = result.scalar_one_or_none()

    if user is None:
        raise credentials_exception

    return user


async def get_current_active_user(
    current_user=Depends(get_current_user),
):
    """
    获取当前活跃用户（可扩展用户状态检查）

    Returns:
        当前活跃用户

    Raises:
        HTTPException 403: 用户已被禁用
    """
    # 后续可在此添加用户状态检查（如是否被封禁）
    return current_user
