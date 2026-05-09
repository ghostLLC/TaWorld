"""
用户模块 — API 路由

提供用户信息查询、更新、位置上报、设备注册、头像上传接口。
"""

from typing import Annotated

from fastapi import APIRouter, Depends, File, UploadFile
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


@router.get("/me/stats", summary="获取用户概览统计")
async def get_my_stats(
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """获取当前用户的概览统计：关系数、提醒统计等"""
    from app.modules.reminders.service import ReminderService
    from app.modules.relationships.service import RelationshipService

    relationships = await RelationshipService.get_user_relationships(
        db, current_user.id
    )
    reminder_stats = await ReminderService.get_user_stats(db, current_user.id)

    return success_response(data={
        "nickname": current_user.nickname,
        "avatar_url": current_user.avatar_url,
        "relationship_count": len([r for r in relationships if r.status.value == "active"]),
        "total_relationships": len(relationships),
        "reminder_stats": reminder_stats,
    })


@router.post("/me/avatar", summary="上传头像")
async def upload_avatar(
    file: Annotated[UploadFile, File(description="头像图片，支持 JPEG/PNG/WebP，最大 2MB")],
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    上传用户头像图片

    - 支持格式: JPEG, PNG, WebP
    - 最大大小: 2MB
    - 上传后自动更新用户 avatar_url
    """
    from app.core.storage import StorageService

    content = await file.read()
    old_url = current_user.avatar_url

    url = await StorageService.upload_avatar(content, file.content_type or "image/jpeg")

    # Delete old avatar if it exists
    if old_url:
        await StorageService.delete_avatar(old_url)

    # Update user
    current_user.avatar_url = url
    await db.flush()
    await db.refresh(current_user)

    return success_response(
        data={"avatar_url": url},
        message="头像上传成功",
    )


@router.delete("/me/avatar", summary="删除头像")
async def delete_avatar(
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """删除当前用户头像，恢复默认"""
    from app.core.storage import StorageService

    if current_user.avatar_url:
        await StorageService.delete_avatar(current_user.avatar_url)

    current_user.avatar_url = None
    await db.flush()
    await db.refresh(current_user)

    return success_response(message="头像已删除")
