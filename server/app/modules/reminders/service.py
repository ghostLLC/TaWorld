"""
提醒模块 — 业务逻辑服务层
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.exceptions import ReminderException
from app.modules.relationships.service import RelationshipService
from app.modules.reminders.models import (
    ReminderConfig,
    ReminderLog,
    ReminderLogStatus,
)
from app.modules.reminders.schemas import (
    ReminderConfigCreate,
    ReminderConfigUpdate,
    ReminderSendRequest,
)


class ReminderService:
    """提醒业务逻辑服务"""

    @staticmethod
    async def create_config(
        db: AsyncSession,
        relationship_id: uuid.UUID,
        user_id: uuid.UUID,
        data: ReminderConfigCreate,
    ) -> ReminderConfig:
        """
        创建提醒配置

        会验证用户是否属于该关系。
        """
        # 验证关系权限
        await RelationshipService.get_relationship(db, relationship_id, user_id)

        config = ReminderConfig(
            relationship_id=relationship_id,
            category=data.category,
            enabled=data.enabled,
            config=data.config,
            created_by=user_id,
        )
        db.add(config)
        await db.flush()
        await db.refresh(config)
        return config

    @staticmethod
    async def get_configs_by_relationship(
        db: AsyncSession,
        relationship_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> list[ReminderConfig]:
        """获取关系下的所有提醒配置"""
        # 验证权限
        await RelationshipService.get_relationship(db, relationship_id, user_id)

        result = await db.execute(
            select(ReminderConfig)
            .where(ReminderConfig.relationship_id == relationship_id)
            .order_by(ReminderConfig.created_at.desc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_config(
        db: AsyncSession,
        config_id: uuid.UUID,
    ) -> ReminderConfig:
        """获取单个提醒配置"""
        result = await db.execute(
            select(ReminderConfig).where(ReminderConfig.id == config_id)
        )
        config = result.scalar_one_or_none()
        if not config:
            raise ReminderException(
                code=ReminderException.NOT_FOUND,
                message="提醒配置不存在",
                status_code=404,
            )
        return config

    @staticmethod
    async def update_config(
        db: AsyncSession,
        config_id: uuid.UUID,
        data: ReminderConfigUpdate,
    ) -> ReminderConfig:
        """更新提醒配置"""
        config = await ReminderService.get_config(db, config_id)
        update_data = data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(config, field, value)
        await db.flush()
        await db.refresh(config)
        return config

    @staticmethod
    async def delete_config(
        db: AsyncSession,
        config_id: uuid.UUID,
    ) -> None:
        """删除提醒配置"""
        config = await ReminderService.get_config(db, config_id)
        await db.delete(config)
        await db.flush()

    @staticmethod
    async def send_reminder(
        db: AsyncSession,
        config_id: uuid.UUID,
        sender_id: uuid.UUID,
        data: ReminderSendRequest,
    ) -> ReminderLog:
        """
        一键提醒（A→B）

        创建提醒日志并标记为已发送。
        """
        config = await ReminderService.get_config(db, config_id)
        relationship = config.relationship_ref

        # 确定接收者
        receiver_id = (
            relationship.user_b_id
            if relationship.user_a_id == sender_id
            else relationship.user_a_id
        )

        log = ReminderLog(
            config_id=config_id,
            sender_id=sender_id,
            receiver_id=receiver_id,
            message=data.message,
            status=ReminderLogStatus.SENT,
            sent_at=datetime.now(timezone.utc),
        )
        db.add(log)
        await db.flush()
        await db.refresh(log)

        # 触发 FCM 推送通知给接收者B
        from app.core.push_service import PushService
        await PushService.send(
            user_id=str(receiver_id),
            title="你收到一条关怀提醒 💝",
            body=data.message or "有人提醒你啦",
            data={
                "type": "reminder",
                "log_id": str(log.id),
                "config_id": str(config_id),
            },
        )

        return log

    @staticmethod
    async def confirm_reminder(
        db: AsyncSession,
        log_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> ReminderLog:
        """
        确认收到提醒（B确认）
        """
        result = await db.execute(
            select(ReminderLog).where(ReminderLog.id == log_id)
        )
        log = result.scalar_one_or_none()

        if not log:
            raise ReminderException(
                code=ReminderException.NOT_FOUND,
                message="提醒记录不存在",
                status_code=404,
            )

        if log.receiver_id != user_id:
            raise ReminderException(
                code=ReminderException.NOT_FOUND,
                message="无权操作此提醒",
                status_code=403,
            )

        if log.status == ReminderLogStatus.CONFIRMED:
            raise ReminderException(
                code=ReminderException.ALREADY_CONFIRMED,
                message="该提醒已被确认",
            )

        log.status = ReminderLogStatus.CONFIRMED
        log.confirmed_at = datetime.now(timezone.utc)
        await db.flush()
        await db.refresh(log)

        # 推送确认通知给发送者A
        from app.core.push_service import PushService
        await PushService.send(
            user_id=str(log.sender_id),
            title="Ta已收到你的关怀 💚",
            body="你的提醒已被确认收到",
            data={
                "type": "confirmation",
                "log_id": str(log.id),
            },
        )

        # 更新成就进度
        from app.modules.achievements.service import AchievementService
        await AchievementService.update_progress(
            db, log.sender_id, "初次守护", increment=1
        )

        return log

    @staticmethod
    async def get_logs(
        db: AsyncSession,
        config_id: uuid.UUID,
        limit: int = 50,
    ) -> list[ReminderLog]:
        """获取提醒历史记录"""
        result = await db.execute(
            select(ReminderLog)
            .where(ReminderLog.config_id == config_id)
            .order_by(ReminderLog.triggered_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_user_stats(
        db: AsyncSession,
        user_id: uuid.UUID,
    ) -> dict:
        """获取用户提醒统计"""
        from datetime import timedelta

        today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        week_ago = today - timedelta(days=7)

        # 总提醒数（发送+接收）
        sent_count = await db.scalar(
            select(func.count(ReminderLog.id)).where(ReminderLog.sender_id == user_id)
        ) or 0
        received_count = await db.scalar(
            select(func.count(ReminderLog.id)).where(ReminderLog.receiver_id == user_id)
        ) or 0

        # 本周提醒数
        week_sent = await db.scalar(
            select(func.count(ReminderLog.id)).where(
                ReminderLog.sender_id == user_id,
                ReminderLog.triggered_at >= week_ago,
            )
        ) or 0

        # 连续活跃天数
        streak = 0
        for day_offset in range(30):
            check_date = (today - timedelta(days=day_offset)).date()
            day_start = datetime(check_date.year, check_date.month, check_date.day, tzinfo=timezone.utc)
            day_end = day_start + timedelta(days=1)
            day_count = await db.scalar(
                select(func.count(ReminderLog.id)).where(
                    ReminderLog.sender_id == user_id,
                    ReminderLog.triggered_at >= day_start,
                    ReminderLog.triggered_at < day_end,
                )
            ) or 0
            if day_count > 0:
                streak += 1
            else:
                break

        # 分类统计
        from app.modules.reminders.models import ReminderConfig, ReminderCategory
        cat_result = await db.execute(
            select(
                ReminderConfig.category,
                func.count(ReminderLog.id),
            )
            .join(ReminderLog, ReminderLog.config_id == ReminderConfig.id)
            .where(ReminderLog.sender_id == user_id)
            .group_by(ReminderConfig.category)
        )
        by_category = {row[0].value: row[1] for row in cat_result.all()}

        return {
            "total_sent": sent_count,
            "total_received": received_count,
            "week_sent": week_sent,
            "active_streak_days": streak,
            "by_category": by_category,
        }
