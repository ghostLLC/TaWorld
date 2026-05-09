"""
成就模块 — Pydantic Schemas
"""

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class AchievementResponse(BaseModel):
    """成就定义响应"""
    id: uuid.UUID
    name: str
    description: str
    icon: str
    category: str
    unlock_condition: dict[str, Any]
    points: int

    model_config = {"from_attributes": True}


class UserAchievementResponse(BaseModel):
    """用户成就进度响应"""
    id: uuid.UUID
    achievement_id: uuid.UUID
    achievement_name: str = ""
    achievement_icon: str = ""
    achievement_description: str = ""
    progress: int
    unlocked: bool
    unlocked_at: datetime | None = None
    points: int = 0

    model_config = {"from_attributes": True}


class AchievementProgressUpdate(BaseModel):
    """成就进度更新（内部使用）"""
    user_id: uuid.UUID
    achievement_name: str
    increment: int = Field(default=1, description="进度增量")
