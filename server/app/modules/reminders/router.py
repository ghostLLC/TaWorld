"""
提醒模块 — API 路由

提供提醒配置 CRUD、一键提醒、确认收到、历史记录接口。
"""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.response import success_response
from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.modules.reminders.schemas import (
    ReminderConfigCreate,
    ReminderConfigResponse,
    ReminderConfigUpdate,
    ReminderLogResponse,
    ReminderSendRequest,
)
from app.modules.reminders.service import ReminderService
from app.modules.users.models import User

router = APIRouter(tags=["提醒"])


# ==================== 提醒配置 ====================

@router.get(
    "/relationships/{relationship_id}/reminders",
    summary="获取关系的提醒配置",
)
async def get_reminder_configs(
    relationship_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """获取指定关系下的所有提醒配置"""
    configs = await ReminderService.get_configs_by_relationship(
        db, relationship_id, current_user.id
    )
    return success_response(
        data=[
            ReminderConfigResponse.model_validate(c).model_dump(mode="json")
            for c in configs
        ]
    )


@router.post(
    "/relationships/{relationship_id}/reminders",
    summary="创建提醒配置",
)
async def create_reminder_config(
    relationship_id: uuid.UUID,
    data: ReminderConfigCreate,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """为指定关系创建新的提醒配置"""
    config = await ReminderService.create_config(
        db, relationship_id, current_user.id, data
    )
    return success_response(
        data=ReminderConfigResponse.model_validate(config).model_dump(mode="json"),
        message="提醒配置已创建",
    )


@router.put("/reminders/{config_id}", summary="更新提醒配置")
async def update_reminder_config(
    config_id: uuid.UUID,
    data: ReminderConfigUpdate,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """更新提醒配置的启用状态或配置详情"""
    config = await ReminderService.update_config(db, config_id, data)
    return success_response(
        data=ReminderConfigResponse.model_validate(config).model_dump(mode="json")
    )


@router.delete("/reminders/{config_id}", summary="删除提醒配置")
async def delete_reminder_config(
    config_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """删除提醒配置"""
    await ReminderService.delete_config(db, config_id)
    return success_response(message="提醒配置已删除")


# ==================== 提醒操作 ====================

@router.post("/reminders/{config_id}/send", summary="一键提醒")
async def send_reminder(
    config_id: uuid.UUID,
    data: ReminderSendRequest,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    一键提醒（A→B）

    触发推送通知给对方。
    """
    log = await ReminderService.send_reminder(
        db, config_id, current_user.id, data
    )
    return success_response(
        data=ReminderLogResponse.model_validate(log).model_dump(mode="json"),
        message="提醒已发送",
    )


@router.post("/reminders/{log_id}/confirm", summary="确认收到提醒")
async def confirm_reminder(
    log_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """B确认收到A的提醒"""
    log = await ReminderService.confirm_reminder(db, log_id, current_user.id)
    return success_response(
        data=ReminderLogResponse.model_validate(log).model_dump(mode="json"),
        message="已确认收到",
    )


# ==================== 提醒历史 ====================

@router.get("/reminders/{config_id}/logs", summary="获取提醒历史")
async def get_reminder_logs(
    config_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """获取指定提醒配置的历史记录"""
    logs = await ReminderService.get_logs(db, config_id)
    return success_response(
        data=[
            ReminderLogResponse.model_validate(log).model_dump(mode="json")
            for log in logs
        ]
    )
