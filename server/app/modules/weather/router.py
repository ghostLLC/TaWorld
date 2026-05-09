"""
天气模块 — API 路由

提供天气查询接口（内部调试用）。
"""

from typing import Annotated

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, Query

from app.common.response import success_response
from app.core.dependencies import get_current_active_user, get_redis
from app.modules.users.models import User
from app.modules.weather.service import WeatherService

router = APIRouter(prefix="/weather", tags=["天气"])


@router.get("/current", summary="查询当前天气")
async def get_current_weather(
    latitude: Annotated[float, Query(ge=-90, le=90, description="纬度")],
    longitude: Annotated[float, Query(ge=-180, le=180, description="经度")],
    current_user: Annotated[User, Depends(get_current_active_user)],
    redis_client: Annotated[aioredis.Redis, Depends(get_redis)],
):
    """
    查询指定位置的当前天气

    主要用于内部调试，正常业务流程中天气由定时任务自动检查。
    """
    weather = await WeatherService.get_current_weather(
        latitude, longitude, redis_client
    )
    return success_response(data=weather.model_dump())
