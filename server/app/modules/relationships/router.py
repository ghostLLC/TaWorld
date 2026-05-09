"""
关系模块 — API 路由

提供关系邀请、加入、查询、更新、解除接口。
"""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.response import success_response
from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.modules.relationships.schemas import (
    InviteRequest,
    InviteResponse,
    JoinRequest,
    RelationshipListItem,
    RelationshipResponse,
    RelationshipUpdate,
)
from app.modules.relationships.service import RelationshipService
from app.modules.users.models import User

router = APIRouter(prefix="/relationships", tags=["关系"])


@router.post("/invite", summary="创建关系邀请")
async def create_invite(
    data: InviteRequest,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """生成邀请码，分享给对方加入"""
    relationship = await RelationshipService.create_invite(db, current_user.id, data)
    return success_response(
        data=InviteResponse.model_validate(relationship).model_dump(mode="json"),
        message="邀请已创建",
    )


@router.post("/join", summary="通过邀请码加入")
async def join_relationship(
    data: JoinRequest,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """通过邀请码加入关系"""
    relationship = await RelationshipService.join_by_invite_code(
        db, current_user.id, data.invite_code
    )
    return success_response(
        data=RelationshipResponse.model_validate(relationship).model_dump(mode="json"),
        message="已成功加入",
    )


@router.get("", summary="获取我的所有关系")
async def get_my_relationships(
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """获取当前用户的所有关系列表（含对方信息）"""
    relationships = await RelationshipService.get_user_relationships(
        db, current_user.id
    )
    items = []
    for r in relationships:
        is_a = r.user_a_id == current_user.id
        partner = r.user_b if is_a else r.user_a
        my_nickname = r.nickname_a_for_b if is_a else r.nickname_b_for_a
        items.append(
            RelationshipListItem(
                id=r.id,
                type=r.type,
                status=r.status,
                partner_id=partner.id if partner else None,
                partner_nickname=partner.nickname if partner else None,
                partner_avatar_url=partner.avatar_url if partner else None,
                my_nickname_for_them=my_nickname,
                created_at=r.created_at,
            ).model_dump(mode="json")
        )
    return success_response(data=items)


@router.get("/{relationship_id}", summary="获取关系详情")
async def get_relationship(
    relationship_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """获取指定关系的详细信息"""
    relationship = await RelationshipService.get_relationship(
        db, relationship_id, current_user.id
    )
    return success_response(
        data=RelationshipResponse.model_validate(relationship).model_dump(mode="json")
    )


@router.put("/{relationship_id}", summary="更新关系")
async def update_relationship(
    relationship_id: uuid.UUID,
    data: RelationshipUpdate,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """更新关系信息（如备注名）"""
    relationship = await RelationshipService.update_relationship(
        db, relationship_id, current_user.id, data
    )
    return success_response(
        data=RelationshipResponse.model_validate(relationship).model_dump(mode="json")
    )


@router.delete("/{relationship_id}", summary="解除关系")
async def dissolve_relationship(
    relationship_id: uuid.UUID,
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """解除关系（软删除，标记为 dissolved）"""
    relationship = await RelationshipService.dissolve_relationship(
        db, relationship_id, current_user.id
    )
    return success_response(message="关系已解除")
