"""
天气模块 — Pydantic Schemas

天气数据不做持久化存储，使用 Redis 缓存。
"""

from pydantic import BaseModel, Field


class WeatherCondition(BaseModel):
    """天气状况"""
    text: str = Field(..., description="天气状况文本，如 '晴', '多云', '小雨'")
    icon: str = Field(default="", description="天气图标代码")
    temp: float = Field(..., description="温度（摄氏度）")
    feels_like: float = Field(..., description="体感温度（摄氏度）")
    humidity: int = Field(..., description="相对湿度（%）")
    wind_dir: str = Field(default="", description="风向")
    wind_scale: str = Field(default="", description="风力等级")


class WeatherResponse(BaseModel):
    """天气查询响应"""
    city: str = Field(..., description="城市名")
    current: WeatherCondition = Field(..., description="当前天气")
    warning: str | None = Field(default=None, description="天气预警信息")
    suggestion: str | None = Field(default=None, description="关怀建议")


class WeatherForecastItem(BaseModel):
    """天气预报单条"""
    date: str = Field(..., description="日期 YYYY-MM-DD")
    text_day: str = Field(..., description="白天天气")
    text_night: str = Field(..., description="夜间天气")
    temp_max: float = Field(..., description="最高温度")
    temp_min: float = Field(..., description="最低温度")


class WeatherCheckResult(BaseModel):
    """天气检查结果（定时任务使用）"""
    should_remind: bool = Field(default=False, description="是否需要提醒")
    condition: str = Field(default="", description="触发条件")
    message: str = Field(default="", description="提醒消息")
    error: str | None = Field(default=None, description="错误信息")
