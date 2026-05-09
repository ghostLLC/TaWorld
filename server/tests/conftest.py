"""
测试配置模块

提供测试用的 fixtures 和工具函数。
"""

import asyncio
from typing import AsyncGenerator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.database import Base, get_db
from app.main import app

# 测试数据库 URL（使用 SQLite 内存数据库进行单元测试）
# 如需使用 PostgreSQL，请修改为实际测试数据库 URL
TEST_DATABASE_URL = "sqlite+aiosqlite:///./test.db"


@pytest.fixture(scope="session")
def event_loop():
    """创建事件循环"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    """
    测试用 HTTP 客户端

    Usage:
        async def test_example(client: AsyncClient):
            response = await client.get("/health")
            assert response.status_code == 200
    """
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest_asyncio.fixture
async def auth_client(client: AsyncClient) -> AsyncClient:
    """
    带认证的测试客户端

    自动注册测试用户并设置 Authorization header。
    """
    # 注册测试用户
    register_data = {
        "phone": "13800138000",
        "password": "test123456",
        "nickname": "测试用户",
    }
    await client.post("/api/v1/auth/register", json=register_data)

    # 登录获取 Token
    login_data = {
        "phone": "13800138000",
        "password": "test123456",
    }
    response = await client.post("/api/v1/auth/login", json=login_data)
    token = response.json()["data"]["access_token"]

    client.headers["Authorization"] = f"Bearer {token}"
    return client
