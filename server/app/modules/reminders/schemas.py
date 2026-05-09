"""
提醒模块 — Pydantic Schemas
"""

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

from app.modules.reminders.models import ReminderCategory, ReminderLogStatus


# ==================== 提醒配置 Schemas ====================

class ReminderConfigCreate(BaseModel):
    """创建提醒配置"""
    category: ReminderCategory = Field(..., description="提醒类别")
    enabled: bool = Field(default=True, description="是否启用")
    config: dict[str, Any] = Field(default_factory=dict, description="配置详情（JSON）")


class ReminderConfigUpdate(BaseModel):
    """更新提醒配置"""
    enabled: bool | None = Field(default=None, description="是否启用")
    config: dict[str, Any] | None = Field(default=None, description="配置详情（JSON）")


class ReminderConfigResponse(BaseModel):
    """提醒配置响应"""
    id: uuid.UUID
    relationship_id: uuid.UUID
    category: ReminderCategory
    enabled: bool
    config: dict[str, Any]
    created_by: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


# ==================== 提醒日志 Schemas ====================

class ReminderSendRequest(BaseModel):
    """一键提醒请求"""
    message: str | None = Field(default=None, max_length=500, description="自定义提醒消息")


class ReminderLogResponse(BaseModel):
    """提醒日志响应"""
    id: uuid.UUID
    config_id: uuid.UUID
    sender_id: uuid.UUID
    receiver_id: uuid.UUID
    message: str | None = None
    status: ReminderLogStatus
    triggered_at: datetime
    sent_at: datetime | None = None
    confirmed_at: datetime | None = None

    model_config = {"from_attributes": True}
