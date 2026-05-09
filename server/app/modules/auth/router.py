"""
认证模块 — API 路由

提供注册、登录、Token刷新接口。
"""

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.response import success_response
from app.core.database import get_db
from app.modules.auth.schemas import (
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
)
from app.modules.auth.service import AuthService
from app.modules.users.schemas import UserResponse

router = APIRouter(prefix="/auth", tags=["认证"])


@router.post("/register", summary="用户注册")
async def register(
    data: RegisterRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    使用手机号和密码注册新用户

    - 手机号格式: 11位中国大陆手机号
    - 密码长度: 6-50 位
    """
    user = await AuthService.register(db, data)
    return success_response(
        data=UserResponse.model_validate(user).model_dump(mode="json"),
        message="注册成功",
    )


@router.post("/login", summary="用户登录")
async def login(
    data: LoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    使用手机号和密码登录，获取 Token

    返回 access_token 和 refresh_token。
    """
    tokens = await AuthService.login(db, data)
    return success_response(data=tokens.model_dump())


@router.post("/refresh", summary="刷新Token")
async def refresh_token(
    data: RefreshRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    使用 refresh_token 获取新的 Token 对

    当 access_token 过期时调用此接口。
    """
    tokens = await AuthService.refresh_token(db, data.refresh_token)
    return success_response(data=tokens.model_dump())
