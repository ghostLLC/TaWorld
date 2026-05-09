"""
认证模块 — 业务逻辑服务层
"""

from jose import JWTError
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.exceptions import AuthException
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.modules.auth.schemas import LoginRequest, RegisterRequest, TokenResponse
from app.modules.users.models import User
from app.modules.users.service import UserService


class AuthService:
    """认证业务逻辑服务"""

    @staticmethod
    async def register(db: AsyncSession, data: RegisterRequest) -> User:
        """
        用户注册

        Args:
            db: 数据库 Session
            data: 注册请求数据

        Returns:
            新创建的用户

        Raises:
            AuthException: 手机号已注册
        """
        # 检查手机号是否已注册
        existing_user = await UserService.get_user_by_phone(db, data.phone)
        if existing_user:
            raise AuthException(
                code=AuthException.USER_EXISTS,
                message="该手机号已注册",
                status_code=400,
            )

        # 创建用户
        user = User(
            phone=data.phone,
            password_hash=hash_password(data.password),
            nickname=data.nickname or f"用户{data.phone[-4:]}",
        )
        db.add(user)
        await db.flush()
        await db.refresh(user)
        return user

    @staticmethod
    async def login(db: AsyncSession, data: LoginRequest) -> TokenResponse:
        """
        用户登录

        Args:
            db: 数据库 Session
            data: 登录请求数据

        Returns:
            包含 access_token 和 refresh_token 的响应

        Raises:
            AuthException: 手机号或密码错误
        """
        # 查找用户
        user = await UserService.get_user_by_phone(db, data.phone)
        if not user:
            raise AuthException(
                code=AuthException.INVALID_CREDENTIALS,
                message="手机号或密码错误",
            )

        # 验证密码
        if not verify_password(data.password, user.password_hash):
            raise AuthException(
                code=AuthException.INVALID_CREDENTIALS,
                message="手机号或密码错误",
            )

        # 生成 Token
        return AuthService._create_tokens(str(user.id))

    @staticmethod
    async def refresh_token(db: AsyncSession, refresh_token: str) -> TokenResponse:
        """
        刷新 Token

        Args:
            db: 数据库 Session
            refresh_token: 刷新令牌

        Returns:
            新的 Token 对

        Raises:
            AuthException: Refresh Token 无效或已过期
        """
        try:
            payload = decode_token(refresh_token)
            user_id: str | None = payload.get("sub")
            token_type: str | None = payload.get("type")

            if user_id is None or token_type != "refresh":
                raise AuthException(
                    code=AuthException.INVALID_REFRESH_TOKEN,
                    message="无效的刷新令牌",
                )
        except JWTError:
            raise AuthException(
                code=AuthException.INVALID_REFRESH_TOKEN,
                message="刷新令牌已过期或无效",
            )

        # 验证用户是否存在
        from uuid import UUID
        user = await UserService.get_user_by_id(db, UUID(user_id))
        return AuthService._create_tokens(str(user.id))

    @staticmethod
    def _create_tokens(user_id: str) -> TokenResponse:
        """生成 access + refresh Token 对"""
        return TokenResponse(
            access_token=create_access_token(data={"sub": user_id}),
            refresh_token=create_refresh_token(data={"sub": user_id}),
        )
