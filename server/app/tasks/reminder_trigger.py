"""
定时提醒触发任务

每分钟检查睡觉/吃饭等定时提醒配置，到达提醒时间时触发。
"""

import logging
from datetime import datetime, timezone, timedelta

from sqlalchemy import select

from app.core.database import async_session_factory
from app.modules.relationships.models import Relationship, RelationshipStatus
from app.modules.reminders.models import (
    ReminderCategory,
    ReminderConfig,
    ReminderLog,
    ReminderLogStatus,
)

logger = logging.getLogger(__name__)

# 中国时区偏移
CST = timezone(timedelta(hours=8))


async def check_timed_reminders() -> None:
    """
    定时提醒检查主任务

    检查睡觉/吃饭类型的提醒配置，判断当前时间是否到达提醒时间。
    """
    now = datetime.now(CST)
    current_time = now.strftime("%H:%M")

    async with async_session_factory() as db:
        try:
            # 查询所有启用的定时提醒（睡觉+吃饭）
            result = await db.execute(
                select(ReminderConfig)
                .join(
                    Relationship,
                    ReminderConfig.relationship_id == Relationship.id,
                )
                .where(
                    ReminderConfig.category.in_([
                        ReminderCategory.SLEEP,
                        ReminderCategory.MEAL,
                    ]),
                    ReminderConfig.enabled == True,
                    Relationship.status == RelationshipStatus.ACTIVE,
                )
            )
            configs = list(result.scalars().all())

            for config in configs:
                await _process_timed_config(db, config, current_time, now)

            await db.commit()

        except Exception as e:
            logger.error(f"❌ 定时提醒检查失败: {e}")
            await db.rollback()


async def _process_timed_config(
    db,
    config: ReminderConfig,
    current_time: str,
    now: datetime,
) -> None:
    """处理单个定时提醒配置"""
    try:
        relationship = config.relationship_ref
        if not relationship or not relationship.user_b_id:
            return

        # 确定通知对象（创建配置的人）和关怀目标（对方）
        notifier_id = config.created_by  # 被提醒去关心的人
        target_id = (
            relationship.user_b_id
            if relationship.user_a_id == notifier_id
            else relationship.user_a_id
        )

        reminder_times = _get_reminder_times(config, target_id)

        for reminder_time, message in reminder_times:
            if current_time == reminder_time:
                today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

                existing = await db.execute(
                    select(ReminderLog).where(
                        ReminderLog.config_id == config.id,
                        ReminderLog.triggered_at >= today_start,
                        ReminderLog.message == message,
                    )
                )
                if existing.scalar_one_or_none():
                    continue

                # 创建提醒日志
                log = ReminderLog(
                    config_id=config.id,
                    sender_id=notifier_id,
                    receiver_id=target_id,
                    message=message,
                    status=ReminderLogStatus.TRIGGERED,
                )
                db.add(log)

                logger.info(
                    f"定时提醒触发: 关系={relationship.id}, "
                    f"类型={config.category.value}, 时间={reminder_time}, "
                    f"通知={notifier_id}"
                )

                from app.core.push_service import PushService
                await PushService.send(
                    user_id=str(notifier_id),
                    title={
                        "sleep": "睡觉时间到 🌙",
                        "meal": "吃饭时间到 🍚",
                    }.get(config.category.value, "关怀提醒 💝"),
                    body=message,
                    data={
                        "type": "timed_reminder",
                        "log_id": str(log.id),
                        "config_id": str(config.id),
                        "category": config.category.value,
                    },
                )

    except Exception as e:
        logger.error(f"处理定时配置 {config.id} 失败: {e}")


def _get_reminder_times(
    config: ReminderConfig,
    target_user_id: str,
) -> list[tuple[str, str]]:
    """
    解析配置中的提醒时间

    使用配置中目标用户的作息时间来计算提醒时刻。

    Returns:
        [(提醒时间, 消息)] 列表
    """
    times = []
    conf = config.config

    if config.category == ReminderCategory.SLEEP:
        sleep_time = conf.get("target_sleep_time", "23:00")
        advance = conf.get("advance_minutes", 30)

        hour, minute = map(int, sleep_time.split(":"))
        remind_dt = datetime(2000, 1, 1, hour, minute) - timedelta(minutes=advance)
        remind_time = remind_dt.strftime("%H:%M")

        times.append((remind_time, f"Ta快到睡觉时间了（{sleep_time}），提醒Ta早点休息吧 🌙"))

    elif config.category == ReminderCategory.MEAL:
        meals = conf.get("meals", [])
        for meal in meals:
            meal_name = meal.get("name", "吃饭")
            meal_time = meal.get("target_time", "12:00")
            advance = meal.get("advance_minutes", 15)

            hour, minute = map(int, meal_time.split(":"))
            remind_dt = datetime(2000, 1, 1, hour, minute) - timedelta(minutes=advance)
            remind_time = remind_dt.strftime("%H:%M")

            times.append((remind_time, f"快到{meal_name}时间了，提醒Ta按时吃饭 🍚"))

    return times
