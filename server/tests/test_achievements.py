"""
成就模块 — 单元测试

验证成就进度更新和解锁逻辑。
"""

import uuid

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
class TestAchievementRoutes:
    """成就路由测试"""

    async def test_get_achievements(self, auth_client: AsyncClient):
        """获取所有成就列表"""
        response = await auth_client.get("/api/v1/achievements")
        assert response.status_code == 200
        data = response.json()
        assert data["code"] == 0
        assert len(data["data"]) >= 7  # 7个预设成就

    async def test_get_my_achievements(self, auth_client: AsyncClient):
        """获取我的成就进度"""
        response = await auth_client.get("/api/v1/users/me/achievements")
        assert response.status_code == 200
        data = response.json()
        assert data["code"] == 0
        assert len(data["data"]) >= 7
        # 所有成就默认进度为0且未解锁
        for item in data["data"]:
            assert item["unlocked"] is False
            assert item["progress"] == 0

    async def test_unauthorized_access(self, client: AsyncClient):
        """未认证访问成就接口"""
        response = await client.get("/api/v1/achievements")
        assert response.status_code == 401
