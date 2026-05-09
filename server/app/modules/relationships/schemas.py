"""
关系模块 — Pydantic Schemas
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.modules.relationships.models import RelationshipStatus, RelationshipType


class InviteRequest(BaseModel):
    """创建邀请请求"""
    type: RelationshipType = Field(
        default=RelationshipType.COUPLE,
        description="关系类型: couple/family/friend",
    )


class InviteResponse(BaseModel):
    """邀请创建响应"""
    id: uuid.UUID
    invite_code: str
    type: RelationshipType
    status: RelationshipStatus
    created_at: datetime

    model_config = {"from_attributes": True}


class JoinRequest(BaseModel):
    """通过邀请码加入"""
    invite_code: str = Field(..., max_length=20, description="邀请码")


class RelationshipUpdate(BaseModel):
    """关系更新请求"""
    nickname_for_partner: str | None = Field(
        default=None, max_length=50, description="给对方的备注名"
    )


class RelationshipResponse(BaseModel):
    """关系详情响应"""
    id: uuid.UUID
    type: RelationshipType
    status: RelationshipStatus
    invite_code: str
    nickname_a_for_b: str | None = None
    nickname_b_for_a: str | None = None
    user_a_id: uuid.UUID
    user_b_id: uuid.UUID | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class RelationshipListItem(BaseModel):
    """关系列表项（含对方信息）"""
    id: uuid.UUID
    type: RelationshipType
    status: RelationshipStatus
    partner_id: uuid.UUID | None = None
    partner_nickname: str | None = None
    partner_avatar_url: str | None = None
    my_nickname_for_them: str | None = None
    created_at: datetime


class RelationshipDetailResponse(RelationshipResponse):
    """关系详情（含双方简要信息）"""
    user_a_name: str | None = None
    user_b_name: str | None = None
