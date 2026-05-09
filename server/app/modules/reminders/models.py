"""
提醒模块 — 数据库模型

包含: ReminderConfig（提醒配置）、ReminderLog（提醒日志）
"""

import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, Enum, ForeignKey, String, Text, DateTime, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, UUIDMixin, TimestampMixin


class ReminderCategory(str, enum.Enum):
    """提醒类别枚举"""
    WEATHER = "weather"     # 天气提醒
    SLEEP = "sleep"         # 睡觉提醒
    MEAL = "meal"           # 吃饭提醒
    CUSTOM = "custom"       # 自定义提醒


class ReminderLogStatus(str, enum.Enum):
    """提醒日志状态枚举"""
    TRIGGERED = "triggered"   # 已触发（系统判定需要提醒）
    SENT = "sent"             # 已发送（A已提醒B）
    CONFIRMED = "confirmed"   # 已确认（B确认收到）


class ReminderConfig(Base, UUIDMixin, TimestampMixin):
    """提醒配置表"""

    __tablename__ = "reminder_configs"

    relationship_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("relationships.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        comment="关联的关系ID",
    )
    category: Mapped[ReminderCategory] = mapped_column(
        Enum(ReminderCategory),
        nullable=False,
        comment="提醒类别",
    )
    enabled: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False, comment="是否启用"
    )
    config: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, comment="灵活配置项（JSON）"
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        comment="创建者用户ID",
    )

    # 关系
    relationship_ref = relationship("Relationship", lazy="selectin")
    logs: Mapped[list["ReminderLog"]] = relationship(
        "ReminderLog", back_populates="config_ref", lazy="noload"
    )

    def __repr__(self) -> str:
        return f"<ReminderConfig(id={self.id}, category={self.category}, enabled={self.enabled})>"


class ReminderLog(Base, UUIDMixin):
    """提醒日志表"""

    __tablename__ = "reminder_logs"

    config_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("reminder_configs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        comment="提醒配置ID",
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        comment="提醒发送者（用户A）",
    )
    receiver_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        comment="提醒接收者（用户B）",
    )
    message: Mapped[str | None] = mapped_column(
        Text, nullable=True, comment="提醒消息内容"
    )
    status: Mapped[ReminderLogStatus] = mapped_column(
        Enum(ReminderLogStatus),
        nullable=False,
        default=ReminderLogStatus.TRIGGERED,
        comment="提醒状态",
    )
    triggered_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        comment="触发时间",
    )
    sent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="发送时间（A提醒B的时间）",
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="确认时间（B确认收到的时间）",
    )

    # 关系
    config_ref: Mapped["ReminderConfig"] = relationship(
        "ReminderConfig", back_populates="logs"
    )

    def __repr__(self) -> str:
        return f"<ReminderLog(id={self.id}, status={self.status})>"
