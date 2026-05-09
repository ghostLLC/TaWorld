"""
认证模块 — 单元测试

覆盖注册、登录、Token 刷新等核心认证流程。
"""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
class TestAuthRegister:
    """用户注册测试"""

    async def test_register_success(self, client: AsyncClient):
        """正常注册"""
        response = await client.post(
            "/api/v1/auth/register",
            json={
                "phone": "13900139000",
                "password": "test123456",
                "nickname": "测试用户",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["code"] == 0
        assert data["data"]["phone"] == "13900139000"

    async def test_register_duplicate_phone(self, client: AsyncClient):
        """重复手机号注册"""
        payload = {
            "phone": "13900139001",
            "password": "test123456",
        }
        await client.post("/api/v1/auth/register", json=payload)
        response = await client.post("/api/v1/auth/register", json=payload)
        assert response.json()["code"] != 0

    async def test_register_invalid_phone(self, client: AsyncClient):
        """无效手机号"""
        response = await client.post(
            "/api/v1/auth/register",
            json={"phone": "12345", "password": "test123456"},
        )
        assert response.status_code == 422


@pytest.mark.asyncio
class TestAuthLogin:
    """用户登录测试"""

    async def test_login_success(self, client: AsyncClient):
        """正常登录"""
        # 先注册
        await client.post(
            "/api/v1/auth/register",
            json={"phone": "13900139010", "password": "test123456"},
        )
        # 再登录
        response = await client.post(
            "/api/v1/auth/login",
            json={"phone": "13900139010", "password": "test123456"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["code"] == 0
        assert "access_token" in data["data"]
        assert "refresh_token" in data["data"]

    async def test_login_wrong_password(self, client: AsyncClient):
        """密码错误"""
        await client.post(
            "/api/v1/auth/register",
            json={"phone": "13900139011", "password": "test123456"},
        )
        response = await client.post(
            "/api/v1/auth/login",
            json={"phone": "13900139011", "password": "wrongpassword"},
        )
        assert response.json()["code"] != 0


@pytest.mark.asyncio
class TestAuthRefresh:
    """Token 刷新测试"""

    async def test_refresh_token_success(self, client: AsyncClient):
        """正常刷新 Token"""
        # 注册并登录
        await client.post(
            "/api/v1/auth/register",
            json={"phone": "13900139020", "password": "test123456"},
        )
        login_resp = await client.post(
            "/api/v1/auth/login",
            json={"phone": "13900139020", "password": "test123456"},
        )
        refresh_token = login_resp.json()["data"]["refresh_token"]

        # 刷新 Token
        response = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": refresh_token},
        )
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data["data"]
