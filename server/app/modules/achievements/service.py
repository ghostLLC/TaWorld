"""
成就模块 — 业务逻辑服务层
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.achievements.models import Achievement, UserAchievement
from app.modules.achievements.schemas import UserAchievementResponse


class AchievementService:
    """成就业务逻辑服务"""

    @staticmethod
    async def get_all_achievements(db: AsyncSession) -> list[Achievement]:
        """获取所有成就定义"""
        result = await db.execute(
            select(Achievement).order_by(Achievement.points.asc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_user_achievements(
        db: AsyncSession,
        user_id: uuid.UUID,
    ) -> list[UserAchievementResponse]:
        """
        获取用户的成就列表（包含进度）

        已解锁和未解锁的成就都会返回。
        """
        # 获取所有成就定义
        all_achievements = await AchievementService.get_all_achievements(db)

        # 获取用户的成就进度
        result = await db.execute(
            select(UserAchievement).where(UserAchievement.user_id == user_id)
        )
        user_achievements_map = {
            ua.achievement_id: ua for ua in result.scalars().all()
        }

        # 合并数据
        items = []
        for achievement in all_achievements:
            ua = user_achievements_map.get(achievement.id)
            items.append(
                UserAchievementResponse(
                    id=ua.id if ua else uuid.uuid4(),
                    achievement_id=achievement.id,
                    achievement_name=achievement.name,
                    achievement_icon=achievement.icon,
                    achievement_description=achievement.description,
                    progress=ua.progress if ua else 0,
                    unlocked=ua.unlocked if ua else False,
                    unlocked_at=ua.unlocked_at if ua else None,
                    points=achievement.points,
                )
            )

        return items

    @staticmethod
    async def update_progress(
        db: AsyncSession,
        user_id: uuid.UUID,
        achievement_name: str,
        increment: int = 1,
    ) -> UserAchievement | None:
        """
        更新成就进度（内部调用）

        如果满足解锁条件，自动解锁成就。

        Args:
            db: 数据库 Session
            user_id: 用户 ID
            achievement_name: 成就名称
            increment: 进度增量

        Returns:
            更新后的用户成就记录，如果成就不存在则返回 None
        """
        # 查找成就定义
        result = await db.execute(
            select(Achievement).where(Achievement.name == achievement_name)
        )
        achievement = result.scalar_one_or_none()
        if not achievement:
            return None

        # 查找或创建用户成就记录
        result = await db.execute(
            select(UserAchievement).where(
                UserAchievement.user_id == user_id,
                UserAchievement.achievement_id == achievement.id,
            )
        )
        user_achievement = result.scalar_one_or_none()

        if not user_achievement:
            user_achievement = UserAchievement(
                user_id=user_id,
                achievement_id=achievement.id,
                progress=0,
                unlocked=False,
            )
            db.add(user_achievement)

        # 已解锁则不再更新
        if user_achievement.unlocked:
            return user_achievement

        # 更新进度
        user_achievement.progress += increment

        # 检查是否满足解锁条件
        target = achievement.unlock_condition.get("target", 1)
        if user_achievement.progress >= target:
            user_achievement.unlocked = True
            user_achievement.unlocked_at = datetime.now(timezone.utc)

        await db.flush()
        return user_achievement

    @staticmethod
    async def seed_achievements(db: AsyncSession) -> None:
        """
        初始化预设成就数据（应用启动时调用）

        仅在成就表为空时执行。
        """
        result = await db.execute(select(Achievement).limit(1))
        if result.scalar_one_or_none():
            return  # 已有数据，跳过

        default_achievements = [
            Achievement(
                name="初次守护",
                description="首次成功完成天气提醒闭环",
                icon="🌂",
                category="weather",
                unlock_condition={"type": "reminder_complete", "target": 1},
                points=10,
            ),
            Achievement(
                name="连续守护7天",
                description="连续7天完成至少1次提醒",
                icon="🔥",
                category="streak",
                unlock_condition={"type": "streak_days", "target": 7},
                points=50,
            ),
            Achievement(
                name="晚安大使",
                description="累计完成30次睡觉提醒",
                icon="🌙",
                category="sleep",
                unlock_condition={"type": "sleep_reminder_count", "target": 30},
                points=100,
            ),
            Achievement(
                name="干饭督导",
                description="累计完成30次吃饭提醒",
                icon="🍚",
                category="meal",
                unlock_condition={"type": "meal_reminder_count", "target": 30},
                points=100,
            ),
            Achievement(
                name="百日陪伴",
                description="关系建立满100天且活跃",
                icon="💯",
                category="milestone",
                unlock_condition={"type": "relationship_days", "target": 100},
                points=200,
            ),
            Achievement(
                name="创意达人",
                description="创建5个自定义提醒",
                icon="🎨",
                category="custom",
                unlock_condition={"type": "custom_reminder_count", "target": 5},
                points=50,
            ),
            Achievement(
                name="双向奔赴",
                description="A和B互相完成提醒各10次",
                icon="❤️",
                category="mutual",
                unlock_condition={"type": "mutual_reminder_count", "target": 10},
                points=150,
            ),
        ]

        for achievement in default_achievements:
            db.add(achievement)

        await db.flush()
