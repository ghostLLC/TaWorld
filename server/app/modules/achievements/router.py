"""
成就模块 — API 路由

提供成就列表查询和用户成就进度查看接口。
"""

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.response import success_response
from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.modules.achievements.schemas import AchievementResponse
from app.modules.achievements.service import AchievementService
from app.modules.users.models import User

router = APIRouter(tags=["成就"])


@router.get("/achievements", summary="获取所有成就列表")
async def get_achievements(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_active_user)],
):
    """获取所有可解锁的成就定义"""
    achievements = await AchievementService.get_all_achievements(db)
    return success_response(
        data=[
            AchievementResponse.model_validate(a).model_dump(mode="json")
            for a in achievements
        ]
    )


@router.get("/users/me/achievements", summary="我的成就")
async def get_my_achievements(
    current_user: Annotated[User, Depends(get_current_active_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """获取当前用户的成就列表及进度"""
    user_achievements = await AchievementService.get_user_achievements(
        db, current_user.id
    )
    return success_response(
        data=[ua.model_dump(mode="json") for ua in user_achievements]
    )
