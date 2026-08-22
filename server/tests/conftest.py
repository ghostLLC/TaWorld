"""
测试配置模块

使用 SQLite 内存数据库进行单元测试，无需外部依赖。
"""

import asyncio
import secrets
from typing import AsyncGenerator

import pytest
import pytest_asyncio

# 测试口令在每次测试进程启动时随机生成，仓库中不保留任何明文凭据
TEST_PASSWORD = "Tp-" + secrets.token_urlsafe(12)


def random_digits(k: int = 8) -> str:
    """生成 k 位随机数字（加密安全），用于拼接测试手机号。"""
    return f"{secrets.randbelow(10 ** k):0{k}d}"



from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.database import Base, get_db
from app.main import app

TEST_DATABASE_URL = "sqlite+aiosqlite:///./test.db"

_test_engine = None
_test_session_factory = None


@pytest.fixture(scope="session")
def event_loop():
    """创建事件循环"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(autouse=True)
async def setup_db():
    """自动为每个测试设置并清理数据库"""
    global _test_engine, _test_session_factory

    _test_engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    _test_session_factory = async_sessionmaker(
        _test_engine, class_=AsyncSession, expire_on_commit=False,
    )

    async with _test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Seed achievement data into test database
    async with _test_session_factory() as session:
        from app.modules.achievements.service import AchievementService
        await AchievementService.seed_achievements(session)
        await session.commit()

    # 覆盖 get_db 依赖
    async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
        async with _test_session_factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = override_get_db

    yield

    app.dependency_overrides.clear()
    async with _test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await _test_engine.dispose()


@pytest_asyncio.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    """测试用 HTTP 客户端"""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest_asyncio.fixture
async def auth_client(client: AsyncClient) -> AsyncClient:
    """
    带认证的测试客户端

    注册测试用户并设置 Authorization header。
    每个测试方法会使用不同的手机号，避免重复注册冲突。
    """
    suffix = random_digits()
    phone = f"138{suffix}"

    register_data = {
        "phone": phone,
        "password": TEST_PASSWORD,
        "nickname": "测试用户",
    }
    await client.post("/api/v1/auth/register", json=register_data)

    login_data = {"phone": phone, "password": TEST_PASSWORD}
    response = await client.post("/api/v1/auth/login", json=login_data)
    token = response.json()["data"]["access_token"]

    client.headers["Authorization"] = f"Bearer {token}"
    return client
