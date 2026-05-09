"""
成就模块 — 业务逻辑服务层
"""

import uuid
from datetime import datetime, timezone, timedelta

from sqlalchemy import select, func
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
        all_achievements = await AchievementService.get_all_achievements(db)

        result = await db.execute(
            select(UserAchievement).where(UserAchievement.user_id == user_id)
        )
        user_achievements_map = {
            ua.achievement_id: ua for ua in result.scalars().all()
        }

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
        context: dict | None = None,
    ) -> UserAchievement | None:
        """
        更新成就进度（内部调用）

        根据成就的 unlock_condition.type 使用不同的判断逻辑：
        - count 型: 简单递增计数
        - streak_days: 检查连续N天活跃
        - mutual_reminder_count: 检查双向互动次数
        - relationship_days: 检查关系天数

        Args:
            db: 数据库 Session
            user_id: 用户 ID
            achievement_name: 成就名称
            increment: 进度增量（count型使用）
            context: 额外上下文（partner_id 等，mutual/relationship型需要）

        Returns:
            更新后的用户成就记录
        """
        result = await db.execute(
            select(Achievement).where(Achievement.name == achievement_name)
        )
        achievement = result.scalar_one_or_none()
        if not achievement:
            return None

        unlock_type = achievement.unlock_condition.get("type", "count")

        # 根据类型计算进度值
        if unlock_type == "streak_days":
            progress = await AchievementService._calc_streak_progress(db, user_id)
        elif unlock_type == "mutual_reminder_count":
            partner_id = (context or {}).get("partner_id")
            progress = await AchievementService._calc_mutual_progress(
                db, user_id, partner_id
            ) if partner_id else 0
        elif unlock_type == "relationship_days":
            partner_id = (context or {}).get("partner_id")
            progress = await AchievementService._calc_relationship_days(
                db, user_id, partner_id
            ) if partner_id else 0
        else:
            # count / reminder_complete / sleep_reminder_count 等简单计数型
            progress = None  # 使用增量模式

        return await AchievementService._apply_progress(
            db, user_id, achievement, increment, progress
        )

    @staticmethod
    async def _apply_progress(
        db: AsyncSession,
        user_id: uuid.UUID,
        achievement: Achievement,
        increment: int,
        absolute_progress: int | None,
    ) -> UserAchievement:
        """应用进度更新并检查解锁"""
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

        if user_achievement.unlocked:
            return user_achievement

        # 更新进度：绝对进度优先，否则增量
        if absolute_progress is not None:
            user_achievement.progress = max(user_achievement.progress, absolute_progress)
        else:
            user_achievement.progress += increment

        target = achievement.unlock_condition.get("target", 1)
        if user_achievement.progress >= target:
            user_achievement.unlocked = True
            user_achievement.unlocked_at = datetime.now(timezone.utc)

        await db.flush()
        return user_achievement

    @staticmethod
    async def _calc_streak_progress(
        db: AsyncSession,
        user_id: uuid.UUID,
    ) -> int:
        """计算用户连续活跃天数（有提醒记录的天数）"""
        from app.modules.reminders.models import ReminderLog

        today = datetime.now(timezone.utc).date()
        streak = 0

        for day_offset in range(30):  # 最多回溯30天
            check_date = today - timedelta(days=day_offset)
            day_start = datetime(check_date.year, check_date.month, check_date.day, tzinfo=timezone.utc)
            day_end = day_start + timedelta(days=1)

            result = await db.execute(
                select(func.count(ReminderLog.id)).where(
                    ReminderLog.sender_id == user_id,
                    ReminderLog.triggered_at >= day_start,
                    ReminderLog.triggered_at < day_end,
                )
            )
            count = result.scalar() or 0

            if count > 0:
                streak += 1
            else:
                break  # 连续中断

        return streak

    @staticmethod
    async def _calc_mutual_progress(
        db: AsyncSession,
        user_id: uuid.UUID,
        partner_id: uuid.UUID,
    ) -> int:
        """计算双向互动次数（A和B互相发送提醒的次数）"""
        from app.modules.reminders.models import ReminderLog, ReminderLogStatus

        # A→B 已发送的提醒数
        result = await db.execute(
            select(func.count(ReminderLog.id)).where(
                ReminderLog.sender_id == user_id,
                ReminderLog.receiver_id == partner_id,
                ReminderLog.status.in_([
                    ReminderLogStatus.SENT, ReminderLogStatus.CONFIRMED,
                ]),
            )
        )
        a_to_b = result.scalar() or 0

        # B→A 已发送的提醒数
        result = await db.execute(
            select(func.count(ReminderLog.id)).where(
                ReminderLog.sender_id == partner_id,
                ReminderLog.receiver_id == user_id,
                ReminderLog.status.in_([
                    ReminderLogStatus.SENT, ReminderLogStatus.CONFIRMED,
                ]),
            )
        )
        b_to_a = result.scalar() or 0

        # 双向奔赴取较小值（双方都需要达到）
        return min(a_to_b, b_to_a)

    @staticmethod
    async def _calc_relationship_days(
        db: AsyncSession,
        user_id: uuid.UUID,
        partner_id: uuid.UUID,
    ) -> int:
        """计算关系建立天数"""
        from app.modules.relationships.models import Relationship, RelationshipStatus

        result = await db.execute(
            select(Relationship.created_at).where(
                Relationship.status == RelationshipStatus.ACTIVE,
                (
                    (Relationship.user_a_id == user_id) & (Relationship.user_b_id == partner_id)
                ) | (
                    (Relationship.user_a_id == partner_id) & (Relationship.user_b_id == user_id)
                ),
            )
        )
        created_at = result.scalar_one_or_none()

        if not created_at:
            return 0

        now = datetime.now(timezone.utc)
        delta = now - created_at.replace(tzinfo=timezone.utc)
        return max(0, delta.days)

    @staticmethod
    async def seed_achievements(db: AsyncSession) -> None:
        """
        初始化预设成就数据（应用启动时调用）

        仅在成就表为空时执行。
        """
        result = await db.execute(select(Achievement).limit(1))
        if result.scalar_one_or_none():
            return

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
