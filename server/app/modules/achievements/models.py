"""
成就模块 — 数据库模型

包含: Achievement（成就定义）、UserAchievement（用户成就进度）
"""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, ForeignKey, Integer, String, DateTime, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, UUIDMixin


class Achievement(Base, UUIDMixin):
    """成就定义表"""

    __tablename__ = "achievements"

    name: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, comment="成就名称"
    )
    description: Mapped[str] = mapped_column(
        String(500), nullable=False, default="", comment="成就描述"
    )
    icon: Mapped[str] = mapped_column(
        String(50), nullable=False, default="🏆", comment="成就图标（emoji）"
    )
    category: Mapped[str] = mapped_column(
        String(50), nullable=False, default="general", comment="成就分类"
    )
    unlock_condition: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, comment="解锁条件（JSON）"
    )
    points: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, comment="成就积分"
    )

    def __repr__(self) -> str:
        return f"<Achievement(name={self.name}, points={self.points})>"


class UserAchievement(Base, UUIDMixin):
    """用户成就进度表"""

    __tablename__ = "user_achievements"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        comment="用户ID",
    )
    achievement_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("achievements.id", ondelete="CASCADE"),
        nullable=False,
        comment="成就ID",
    )
    progress: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, comment="当前进度"
    )
    unlocked: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, comment="是否已解锁"
    )
    unlocked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="解锁时间",
    )

    # 关系
    achievement: Mapped["Achievement"] = relationship("Achievement", lazy="selectin")

    def __repr__(self) -> str:
        return f"<UserAchievement(user={self.user_id}, achievement={self.achievement_id}, unlocked={self.unlocked})>"
