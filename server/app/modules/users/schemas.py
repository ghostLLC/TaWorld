"""
用户模块 — Pydantic Schemas

定义 API 请求和响应的数据验证模型。
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


# ==================== 用户 Schemas ====================

class UserBase(BaseModel):
    """用户基础信息"""
    nickname: str = Field(default="", max_length=50, description="昵称")
    avatar_url: str | None = Field(default=None, max_length=500, description="头像URL")


class UserResponse(UserBase):
    """用户响应模型"""
    id: uuid.UUID
    phone: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    """用户信息更新请求"""
    nickname: str | None = Field(default=None, max_length=50, description="昵称")
    avatar_url: str | None = Field(default=None, max_length=500, description="头像URL")


class UserBriefResponse(BaseModel):
    """用户简要信息（用于关系列表等场景）"""
    id: uuid.UUID
    nickname: str
    avatar_url: str | None = None

    model_config = {"from_attributes": True}


# ==================== 位置 Schemas ====================

class LocationUpdate(BaseModel):
    """位置更新请求"""
    latitude: float = Field(..., ge=-90, le=90, description="纬度")
    longitude: float = Field(..., ge=-180, le=180, description="经度")
    city: str | None = Field(default=None, max_length=100, description="城市")
    district: str | None = Field(default=None, max_length=100, description="区/县")


class LocationResponse(BaseModel):
    """位置响应模型"""
    latitude: float
    longitude: float
    city: str | None = None
    district: str | None = None
    updated_at: datetime

    model_config = {"from_attributes": True}


# ==================== 设备 Schemas ====================

class DeviceRegister(BaseModel):
    """设备注册请求"""
    fcm_token: str = Field(..., max_length=500, description="FCM推送Token")
    device_info: str | None = Field(default=None, max_length=500, description="设备信息")


class DeviceResponse(BaseModel):
    """设备响应模型"""
    id: uuid.UUID
    fcm_token: str
    device_info: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}
