"""
天气模块 — 业务逻辑服务层

集成和风天气 API，提供天气查询和条件判断功能。
使用 Redis 缓存天气数据，减少 API 调用。
"""

import json
import logging
from typing import Any

import httpx
import redis.asyncio as aioredis

from app.common.exceptions import SystemException
from app.core.config import get_settings
from app.modules.weather.schemas import (
    WeatherCheckResult,
    WeatherCondition,
    WeatherResponse,
)

settings = get_settings()
logger = logging.getLogger(__name__)

# 需要提醒的天气条件关键词
ALERT_CONDITIONS = {
    "rain": ["小雨", "中雨", "大雨", "暴雨", "阵雨", "雷阵雨"],
    "snow": ["小雪", "中雪", "大雪", "暴雪", "雨夹雪"],
    "extreme_cold": [],  # 通过温度判断
    "extreme_heat": [],  # 通过温度判断
}

# 默认提醒消息模板
DEFAULT_MESSAGES = {
    "rain": "Ta那边要下雨了，提醒Ta带伞吧 🌂",
    "snow": "Ta那边要下雪啦，提醒Ta注意保暖 ❄️",
    "extreme_cold": "Ta那边好冷啊（{temp}°C），提醒Ta多穿点 🧣",
    "extreme_heat": "Ta那边好热啊（{temp}°C），提醒Ta注意防暑 ☀️",
}


class WeatherService:
    """天气业务逻辑服务"""

    @staticmethod
    async def get_current_weather(
        latitude: float,
        longitude: float,
        redis_client: aioredis.Redis | None = None,
    ) -> WeatherResponse:
        """
        获取当前天气（带缓存）

        Args:
            latitude: 纬度
            longitude: 经度
            redis_client: Redis 客户端（可选，用于缓存）

        Returns:
            天气响应数据
        """
        location = f"{longitude},{latitude}"
        cache_key = f"weather:current:{location}"

        # 尝试从缓存读取
        if redis_client:
            cached = await redis_client.get(cache_key)
            if cached:
                logger.debug(f"天气缓存命中: {location}")
                return WeatherResponse(**json.loads(cached))

        # 调用和风天气 API
        weather_data = await WeatherService._fetch_from_qweather(location)

        # 写入缓存（30分钟过期）
        if redis_client and weather_data:
            await redis_client.setex(
                cache_key,
                1800,  # 30 minutes
                json.dumps(weather_data.model_dump(), ensure_ascii=False),
            )

        return weather_data

    @staticmethod
    async def check_weather_condition(
        latitude: float,
        longitude: float,
        notify_conditions: list[str],
        redis_client: aioredis.Redis | None = None,
    ) -> WeatherCheckResult:
        """
        检查天气是否满足提醒条件

        Args:
            latitude: 纬度
            longitude: 经度
            notify_conditions: 需要提醒的条件列表
            redis_client: Redis 客户端

        Returns:
            天气检查结果
        """
        try:
            weather = await WeatherService.get_current_weather(
                latitude, longitude, redis_client
            )
        except Exception as e:
            logger.error(f"天气查询失败: {e}")
            return WeatherCheckResult(should_remind=False, error=str(e))

        current = weather.current

        # 检查各类条件
        for condition in notify_conditions:
            if condition == "rain":
                for keyword in ALERT_CONDITIONS["rain"]:
                    if keyword in current.text:
                        return WeatherCheckResult(
                            should_remind=True,
                            condition="rain",
                            message=DEFAULT_MESSAGES["rain"],
                        )

            elif condition == "snow":
                for keyword in ALERT_CONDITIONS["snow"]:
                    if keyword in current.text:
                        return WeatherCheckResult(
                            should_remind=True,
                            condition="snow",
                            message=DEFAULT_MESSAGES["snow"],
                        )

            elif condition == "extreme_cold" and current.temp <= 0:
                return WeatherCheckResult(
                    should_remind=True,
                    condition="extreme_cold",
                    message=DEFAULT_MESSAGES["extreme_cold"].format(temp=current.temp),
                )

            elif condition == "extreme_heat" and current.temp >= 35:
                return WeatherCheckResult(
                    should_remind=True,
                    condition="extreme_heat",
                    message=DEFAULT_MESSAGES["extreme_heat"].format(temp=current.temp),
                )

        return WeatherCheckResult(should_remind=False)

    @staticmethod
    async def _fetch_from_qweather(location: str) -> WeatherResponse:
        """
        调用和风天气 API 获取实时天气

        Args:
            location: 经度,纬度 格式的位置字符串

        Returns:
            解析后的天气响应

        Raises:
            ValueError: API Key 未配置
        """
        if not settings.QWEATHER_API_KEY:
            raise ValueError("QWeather API Key 未配置，请在 .env 中设置 QWEATHER_API_KEY")

        url = f"{settings.QWEATHER_BASE_URL}/weather/now"
        params = {
            "location": location,
            "key": settings.QWEATHER_API_KEY,
            "lang": "zh",
        }

        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(url, params=params)
            data = response.json()

        if response.status_code != 200 or data.get("code") != "200":
            logger.error(
                f"和风天气 API 错误 | status={response.status_code} | "
                f"code={data.get('code')} | location={location}"
            )
            raise SystemException(
                code=SystemException.EXTERNAL_SERVICE_ERROR,
                message=f"天气服务暂不可用",
            )

        now = data.get("now", {})
        return WeatherResponse(
            city=location,
            current=WeatherCondition(
                text=now.get("text", "未知"),
                icon=now.get("icon", ""),
                temp=float(now.get("temp", 0)),
                feels_like=float(now.get("feelsLike", 0)),
                humidity=int(now.get("humidity", 0)),
                wind_dir=now.get("windDir", ""),
                wind_scale=now.get("windScale", ""),
            ),
        )
