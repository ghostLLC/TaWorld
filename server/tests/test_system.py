"""
系统接口 — 单元测试

覆盖健康检查等基础接口。
"""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
class TestSystem:
    """系统接口测试"""

    async def test_root(self, client: AsyncClient):
        """根路由"""
        response = await client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["code"] == 0
        assert "TaWorld" in data["message"]

    async def test_health_check(self, client: AsyncClient):
        """健康检查"""
        response = await client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"
