"""
天气检查定时任务

每小时扫描所有活跃关系，检查对方所在地天气是否满足提醒条件。
如果满足，触发提醒通知。
"""

import logging

from sqlalchemy import select

from app.core.database import async_session_factory
from app.core.dependencies import get_redis
from app.modules.relationships.models import Relationship, RelationshipStatus
from app.modules.reminders.models import ReminderCategory, ReminderConfig, ReminderLog, ReminderLogStatus
from app.modules.users.models import UserLocation
from app.modules.weather.service import WeatherService

logger = logging.getLogger(__name__)


async def check_weather_for_all_relationships() -> None:
    """
    天气检查主任务

    流程:
    1. 查询所有活跃关系中启用的天气提醒配置
    2. 根据对方位置查询天气
    3. 判断是否满足提醒条件
    4. 满足则创建提醒日志并触发推送
    """
    logger.info("🌦️ 开始天气检查任务...")

    try:
        redis_client = await get_redis()
    except Exception:
        redis_client = None
        logger.warning("Redis 不可用，天气缓存将被跳过")

    async with async_session_factory() as db:
        try:
            # 查询所有活跃关系的天气提醒配置
            result = await db.execute(
                select(ReminderConfig)
                .join(
                    Relationship,
                    ReminderConfig.relationship_id == Relationship.id,
                )
                .where(
                    ReminderConfig.category == ReminderCategory.WEATHER,
                    ReminderConfig.enabled == True,
                    Relationship.status == RelationshipStatus.ACTIVE,
                )
            )
            configs = list(result.scalars().all())

            if not configs:
                logger.info("没有需要检查的天气提醒配置")
                return

            logger.info(f"找到 {len(configs)} 个天气提醒配置")

            for config in configs:
                await _process_weather_config(db, config, redis_client)

            await db.commit()
            logger.info("✅ 天气检查任务完成")

        except Exception as e:
            logger.error(f"❌ 天气检查任务失败: {e}")
            await db.rollback()


async def _process_weather_config(db, config: ReminderConfig, redis_client) -> None:
    """处理单个天气提醒配置"""
    try:
        relationship = config.relationship_ref
        if not relationship:
            return

        # 确定需要查询天气的用户（对方）
        # A 创建了提醒，查询 B 的位置天气来提醒 A
        user_a_id = relationship.user_a_id
        user_b_id = relationship.user_b_id

        if not user_b_id:
            return

        # 获取 B 的位置
        result = await db.execute(
            select(UserLocation).where(UserLocation.user_id == user_b_id)
        )
        location_b = result.scalar_one_or_none()
        if not location_b:
            return

        # 获取提醒条件
        notify_conditions = config.config.get("notify_conditions", ["rain", "snow"])

        # 检查天气
        check_result = await WeatherService.check_weather_condition(
            latitude=location_b.latitude,
            longitude=location_b.longitude,
            notify_conditions=notify_conditions,
            redis_client=redis_client,
        )

        if check_result.should_remind:
            # 使用自定义消息或默认消息
            custom_messages = config.config.get("custom_messages", {})
            message = custom_messages.get(check_result.condition, check_result.message)

            # 创建提醒日志
            log = ReminderLog(
                config_id=config.id,
                sender_id=user_a_id,
                receiver_id=user_a_id,  # 先提醒 A 去关心 B
                message=message,
                status=ReminderLogStatus.TRIGGERED,
            )
            db.add(log)

            logger.info(
                f"天气提醒触发: 关系={relationship.id}, "
                f"条件={check_result.condition}, 消息={message}"
            )

            # 通过 FCM 推送通知给 A
            from app.core.push_service import PushService
            await PushService.send(
                user_id=str(user_a_id),
                title="天气提醒 🌦️",
                body=message,
                data={
                    "type": "weather_reminder",
                    "log_id": str(log.id),
                    "config_id": str(config.id),
                    "condition": check_result.condition,
                },
            )

    except Exception as e:
        logger.error(f"处理天气配置 {config.id} 失败: {e}")
