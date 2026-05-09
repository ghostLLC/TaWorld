"""
用户模块 — API 路由

提供用户信息查询、更新、位置上报、设备注册接口。
"""

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.response import success_response
from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.modules.users.models import User
from app.modules.users.schemas import (
    DeviceRegister,
    DeviceResponse,
    LocationResponse,
    LocationUpdate,
    UserResponse,
    UserUpdate,
)
from app.modules.users.service import UserService

router = APIRouter(prefix="/users", tags=["用户"])


@router.get("/me", summary="获取当前用户信息")
async def get_me(
    current_user: Annotated[User, Depends(get_current_active_user)],
):
    """获取当前登录用户的详细信息"""
    return success_response(
        data=UserResponse.model_validate(current_user).model_dump(mode="json")
    )


@router.put("/me", summary="更新当前用户信息")
async def update_me(
    data: UserUpdate,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """更新当前登录用户的昵称、头像等信息"""
    user = await UserService.update_user(db, current_user, data)
    return success_response(
        data=UserResponse.model_validate(user).model_dump(mode="json")
    )


@router.put("/me/location", summary="上报用户位置")
async def update_location(
    data: LocationUpdate,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    上报当前用户的地理位置

    位置信息用于天气查询，不会暴露给其他用户。
    """
    location = await UserService.update_location(db, current_user.id, data)
    return success_response(
        data=LocationResponse.model_validate(location).model_dump(mode="json")
    )


@router.post("/me/devices", summary="注册设备")
async def register_device(
    data: DeviceRegister,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """注册用户设备，存储 FCM 推送 Token"""
    device = await UserService.register_device(db, current_user.id, data)
    return success_response(
        data=DeviceResponse.model_validate(device).model_dump(mode="json")
    )
