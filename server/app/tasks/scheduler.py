"""
定时任务调度器

使用 APScheduler 管理定时任务，在 FastAPI 启动/关闭时自动管理生命周期。
"""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger

logger = logging.getLogger(__name__)

# 全局调度器实例
scheduler = AsyncIOScheduler()


def init_scheduler() -> None:
    """
    初始化并注册所有定时任务

    在 FastAPI startup 事件中调用。
    """
    from app.tasks.weather_check import check_weather_for_all_relationships
    from app.tasks.reminder_trigger import check_timed_reminders

    # 天气检查：每小时执行一次
    scheduler.add_job(
        check_weather_for_all_relationships,
        trigger=IntervalTrigger(hours=1),
        id="weather_check",
        name="天气检查任务",
        replace_existing=True,
    )

    # 定时提醒检查：每分钟执行一次
    scheduler.add_job(
        check_timed_reminders,
        trigger=IntervalTrigger(minutes=1),
        id="timed_reminder_check",
        name="定时提醒检查任务",
        replace_existing=True,
    )

    scheduler.start()
    logger.info("✅ 定时任务调度器已启动")


def shutdown_scheduler() -> None:
    """
    关闭调度器

    在 FastAPI shutdown 事件中调用。
    """
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("⏹️ 定时任务调度器已关闭")
