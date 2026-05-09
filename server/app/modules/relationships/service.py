"""
关系模块 — 业务逻辑服务层
"""

import secrets
import uuid

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.exceptions import RelationshipException
from app.modules.relationships.models import (
    Relationship,
    RelationshipStatus,
    RelationshipType,
)
from app.modules.relationships.schemas import InviteRequest, RelationshipUpdate


class RelationshipService:
    """关系业务逻辑服务"""

    @staticmethod
    def _generate_invite_code() -> str:
        """生成 8 位随机邀请码"""
        return secrets.token_urlsafe(6)[:8].upper()

    @staticmethod
    async def create_invite(
        db: AsyncSession,
        user_id: uuid.UUID,
        data: InviteRequest,
    ) -> Relationship:
        """
        创建关系邀请

        生成唯一邀请码，等待对方加入。
        """
        relationship = Relationship(
            user_a_id=user_id,
            type=data.type,
            status=RelationshipStatus.PENDING,
            invite_code=RelationshipService._generate_invite_code(),
        )
        db.add(relationship)
        await db.flush()
        await db.refresh(relationship)
        return relationship

    @staticmethod
    async def join_by_invite_code(
        db: AsyncSession,
        user_id: uuid.UUID,
        invite_code: str,
    ) -> Relationship:
        """
        通过邀请码加入关系

        Raises:
            RelationshipException: 邀请码无效、已被使用、或试图自己加入自己的邀请
        """
        # 查找邀请
        result = await db.execute(
            select(Relationship).where(Relationship.invite_code == invite_code)
        )
        relationship = result.scalar_one_or_none()

        if not relationship:
            raise RelationshipException(
                code=RelationshipException.INVITE_INVALID,
                message="邀请码无效",
                status_code=404,
            )

        if relationship.status != RelationshipStatus.PENDING:
            raise RelationshipException(
                code=RelationshipException.INVITE_EXPIRED,
                message="该邀请已被使用或已过期",
            )

        if relationship.user_a_id == user_id:
            raise RelationshipException(
                code=RelationshipException.CANNOT_INVITE_SELF,
                message="不能加入自己创建的邀请",
            )

        # 检查是否已有活跃关系
        existing = await RelationshipService._check_existing_active(
            db, relationship.user_a_id, user_id
        )
        if existing:
            raise RelationshipException(
                code=RelationshipException.ALREADY_PAIRED,
                message="你们之间已存在活跃的关系",
            )

        # 加入关系
        relationship.user_b_id = user_id
        relationship.status = RelationshipStatus.ACTIVE
        await db.flush()
        await db.refresh(relationship)
        return relationship

    @staticmethod
    async def get_user_relationships(
        db: AsyncSession,
        user_id: uuid.UUID,
    ) -> list[Relationship]:
        """获取用户的所有关系"""
        result = await db.execute(
            select(Relationship).where(
                or_(
                    Relationship.user_a_id == user_id,
                    Relationship.user_b_id == user_id,
                )
            ).order_by(Relationship.created_at.desc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_relationship(
        db: AsyncSession,
        relationship_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> Relationship:
        """
        获取关系详情（需要权限验证）

        Raises:
            RelationshipException: 关系不存在或无权限
        """
        result = await db.execute(
            select(Relationship).where(Relationship.id == relationship_id)
        )
        relationship = result.scalar_one_or_none()

        if not relationship:
            raise RelationshipException(
                code=RelationshipException.NOT_FOUND,
                message="关系不存在",
                status_code=404,
            )

        # 权限检查
        if relationship.user_a_id != user_id and relationship.user_b_id != user_id:
            raise RelationshipException(
                code=RelationshipException.NOT_FOUND,
                message="关系不存在",
                status_code=404,
            )

        return relationship

    @staticmethod
    async def update_relationship(
        db: AsyncSession,
        relationship_id: uuid.UUID,
        user_id: uuid.UUID,
        data: RelationshipUpdate,
    ) -> Relationship:
        """更新关系信息（备注名等）"""
        relationship = await RelationshipService.get_relationship(
            db, relationship_id, user_id
        )

        if data.nickname_for_partner is not None:
            if relationship.user_a_id == user_id:
                relationship.nickname_a_for_b = data.nickname_for_partner
            else:
                relationship.nickname_b_for_a = data.nickname_for_partner

        await db.flush()
        await db.refresh(relationship)
        return relationship

    @staticmethod
    async def dissolve_relationship(
        db: AsyncSession,
        relationship_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> Relationship:
        """解除关系"""
        relationship = await RelationshipService.get_relationship(
            db, relationship_id, user_id
        )
        relationship.status = RelationshipStatus.DISSOLVED
        await db.flush()
        await db.refresh(relationship)
        return relationship

    @staticmethod
    async def _check_existing_active(
        db: AsyncSession,
        user_a_id: uuid.UUID,
        user_b_id: uuid.UUID,
    ) -> Relationship | None:
        """检查两个用户之间是否已有活跃关系"""
        result = await db.execute(
            select(Relationship).where(
                Relationship.status == RelationshipStatus.ACTIVE,
                or_(
                    (Relationship.user_a_id == user_a_id) & (Relationship.user_b_id == user_b_id),
                    (Relationship.user_a_id == user_b_id) & (Relationship.user_b_id == user_a_id),
                ),
            )
        )
        return result.scalar_one_or_none()
