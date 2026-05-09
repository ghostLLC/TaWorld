"""
应用配置管理模块

使用 pydantic-settings 从环境变量加载配置，支持 .env 文件。
"""

from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """应用全局配置"""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # ==================== 应用配置 ====================
    APP_NAME: str = "TaWorld"
    APP_VERSION: str = "0.1.0"
    DEBUG: bool = False
    API_V1_PREFIX: str = "/api/v1"

    # ==================== 数据库配置 ====================
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/taworld"

    # ==================== Redis 配置 ====================
    REDIS_URL: str = "redis://localhost:6379/0"

    # ==================== JWT 认证配置 ====================
    JWT_SECRET_KEY: str = "your-super-secret-key-change-this-in-production"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # ==================== 和风天气 API ====================
    QWEATHER_API_KEY: str = ""
    QWEATHER_BASE_URL: str = "https://devapi.qweather.com/v7"

    # ==================== AI 服务配置 ====================
    LLM_API_KEY: str = ""
    LLM_BASE_URL: str = "https://api.openai.com/v1"
    LLM_MODEL: str = "gpt-4o-mini"

    # ==================== 对象存储配置 ====================
    MINIO_ENDPOINT: str = ""
    MINIO_ACCESS_KEY: str = ""
    MINIO_SECRET_KEY: str = ""
    MINIO_BUCKET: str = "taworld"

    # ==================== FCM 推送配置 ====================
    FCM_SERVER_KEY: str = ""

    @property
    def database_url_sync(self) -> str:
        """同步数据库 URL（Alembic 迁移使用）"""
        return self.DATABASE_URL.replace("+asyncpg", "+psycopg2")


@lru_cache
def get_settings() -> Settings:
    """获取全局配置单例"""
    return Settings()
