"""
用户模块 — 数据库模型

包含: User（用户）、UserLocation（用户位置）、Device（设备）
"""

import uuid
from datetime import datetime

from sqlalchemy import Float, ForeignKey, String, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, TimestampMixin, UUIDMixin


class User(Base, UUIDMixin, TimestampMixin):
    """用户表"""

    __tablename__ = "users"

    phone: Mapped[str] = mapped_column(
        String(20), unique=True, index=True, nullable=False, comment="手机号"
    )
    nickname: Mapped[str] = mapped_column(
        String(50), nullable=False, default="", comment="昵称"
    )
    avatar_url: Mapped[str | None] = mapped_column(
        String(500), nullable=True, comment="头像URL"
    )
    password_hash: Mapped[str] = mapped_column(
        String(200), nullable=False, comment="密码哈希"
    )

    # 关系
    location: Mapped["UserLocation | None"] = relationship(
        "UserLocation", back_populates="user", uselist=False, lazy="selectin"
    )
    devices: Mapped[list["Device"]] = relationship(
        "Device", back_populates="user", lazy="selectin"
    )

    def __repr__(self) -> str:
        return f"<User(id={self.id}, phone={self.phone}, nickname={self.nickname})>"


class UserLocation(Base):
    """用户位置表（一对一）"""

    __tablename__ = "user_locations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
        comment="用户ID",
    )
    latitude: Mapped[float] = mapped_column(
        Float, nullable=False, comment="纬度"
    )
    longitude: Mapped[float] = mapped_column(
        Float, nullable=False, comment="经度"
    )
    city: Mapped[str | None] = mapped_column(
        String(100), nullable=True, comment="城市"
    )
    district: Mapped[str | None] = mapped_column(
        String(100), nullable=True, comment="区/县"
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # 关系
    user: Mapped["User"] = relationship("User", back_populates="location")

    def __repr__(self) -> str:
        return f"<UserLocation(user_id={self.user_id}, city={self.city})>"


class Device(Base, UUIDMixin):
    """用户设备表（FCM Token 管理）"""

    __tablename__ = "devices"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        comment="用户ID",
    )
    fcm_token: Mapped[str] = mapped_column(
        String(500), nullable=False, comment="FCM推送Token"
    )
    device_info: Mapped[str | None] = mapped_column(
        String(500), nullable=True, comment="设备信息"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # 关系
    user: Mapped["User"] = relationship("User", back_populates="devices")

    def __repr__(self) -> str:
        return f"<Device(id={self.id}, user_id={self.user_id})>"
