"""
关系模块 — 数据库模型

包含: Relationship（一对一关系）及其枚举类型
"""

import enum
import uuid
from datetime import datetime

from sqlalchemy import Enum, ForeignKey, String, DateTime, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, UUIDMixin


class RelationshipType(str, enum.Enum):
    """关系类型枚举"""
    COUPLE = "couple"       # 情侣
    FAMILY = "family"       # 家人
    FRIEND = "friend"       # 朋友


class RelationshipStatus(str, enum.Enum):
    """关系状态枚举"""
    PENDING = "pending"     # 待接受
    ACTIVE = "active"       # 活跃
    DISSOLVED = "dissolved" # 已解除


class Relationship(Base, UUIDMixin):
    """关系表"""

    __tablename__ = "relationships"

    user_a_id: Mapped[uuid.UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        comment="用户A（邀请方）",
    )
    user_b_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
        comment="用户B（被邀请方，待接受时为空）",
    )
    type: Mapped[RelationshipType] = mapped_column(
        Enum(RelationshipType),
        nullable=False,
        default=RelationshipType.COUPLE,
        comment="关系类型",
    )
    status: Mapped[RelationshipStatus] = mapped_column(
        Enum(RelationshipStatus),
        nullable=False,
        default=RelationshipStatus.PENDING,
        comment="关系状态",
    )
    invite_code: Mapped[str] = mapped_column(
        String(20), unique=True, index=True, nullable=False, comment="邀请码"
    )
    nickname_a_for_b: Mapped[str | None] = mapped_column(
        String(50), nullable=True, comment="A给B的备注名"
    )
    nickname_b_for_a: Mapped[str | None] = mapped_column(
        String(50), nullable=True, comment="B给A的备注名"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # 关系
    user_a = relationship("User", foreign_keys=[user_a_id], lazy="selectin")
    user_b = relationship("User", foreign_keys=[user_b_id], lazy="selectin")

    def __repr__(self) -> str:
        return f"<Relationship(id={self.id}, a={self.user_a_id}, b={self.user_b_id}, status={self.status})>"
