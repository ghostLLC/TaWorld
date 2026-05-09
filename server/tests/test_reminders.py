"""
提醒模块 — 集成测试

覆盖提醒配置CRUD、一键提醒、确认流程。
"""

import random
import uuid

import pytest
from httpx import AsyncClient


async def _create_relationship(client: AsyncClient) -> tuple[str, str, str, str]:
    """辅助函数：创建两个用户并建立关系，返回 (token_a, token_b, user_a_id, rel_id)"""
    s_a = ''.join(random.choices('0123456789', k=8))
    s_b = ''.join(random.choices('0123456789', k=8))

    await client.post("/api/v1/auth/register", json={"phone": f"138{s_a}", "password": "testpass"})
    await client.post("/api/v1/auth/register", json={"phone": f"138{s_b}", "password": "testpass"})

    r = await client.post("/api/v1/auth/login", json={"phone": f"138{s_a}", "password": "testpass"})
    ta = r.json()["data"]["access_token"]
    r = await client.post("/api/v1/auth/login", json={"phone": f"138{s_b}", "password": "testpass"})
    tb = r.json()["data"]["access_token"]

    client.headers["Authorization"] = f"Bearer {ta}"
    inv = await client.post("/api/v1/relationships/invite", json={"type": "friend"})
    code = inv.json()["data"]["invite_code"]
    rel_id = inv.json()["data"]["id"]

    client.headers["Authorization"] = f"Bearer {tb}"
    joined = await client.post("/api/v1/relationships/join", json={"invite_code": code})

    # Get user IDs from relationship
    client.headers["Authorization"] = f"Bearer {ta}"
    rel = await client.get(f"/api/v1/relationships/{rel_id}")
    rel_data = rel.json()["data"]
    uid_a = rel_data["user_a_id"]

    return ta, tb, uid_a, rel_id


@pytest.mark.asyncio
class TestReminderConfigCRUD:
    """提醒配置 CRUD 测试"""

    async def test_create_and_list_config(self, client: AsyncClient):
        """创建提醒配置并列表查询"""
        ta, tb, uid_a, rel_id = await _create_relationship(client)

        client.headers["Authorization"] = f"Bearer {ta}"
        create_resp = await client.post(
            f"/api/v1/relationships/{rel_id}/reminders",
            json={
                "category": "weather",
                "enabled": True,
                "config": {"notify_conditions": ["rain", "snow"]},
            },
        )
        assert create_resp.status_code == 200
        assert create_resp.json()["data"]["category"] == "weather"

        # 查询配置列表
        list_resp = await client.get(f"/api/v1/relationships/{rel_id}/reminders")
        assert list_resp.status_code == 200
        assert len(list_resp.json()["data"]) >= 1

    async def test_update_config(self, client: AsyncClient):
        """更新提醒配置的启用状态"""
        ta, tb, uid_a, rel_id = await _create_relationship(client)

        client.headers["Authorization"] = f"Bearer {ta}"
        create = await client.post(
            f"/api/v1/relationships/{rel_id}/reminders",
            json={"category": "sleep", "enabled": True, "config": {}},
        )
        config_id = create.json()["data"]["id"]

        update = await client.put(
            f"/api/v1/reminders/{config_id}",
            json={"enabled": False},
        )
        assert update.status_code == 200
        assert update.json()["data"]["enabled"] is False

    async def test_delete_config(self, client: AsyncClient):
        """删除提醒配置"""
        ta, tb, uid_a, rel_id = await _create_relationship(client)

        client.headers["Authorization"] = f"Bearer {ta}"
        create = await client.post(
            f"/api/v1/relationships/{rel_id}/reminders",
            json={"category": "custom", "enabled": True, "config": {}},
        )
        config_id = create.json()["data"]["id"]

        delete = await client.delete(f"/api/v1/reminders/{config_id}")
        assert delete.status_code == 200

        # 确认已删除
        list_resp = await client.get(f"/api/v1/relationships/{rel_id}/reminders")
        ids = [c["id"] for c in list_resp.json()["data"]]
        assert config_id not in ids

    async def test_create_config_without_relationship_access(self, client: AsyncClient):
        """不能为不属于自己的关系创建提醒配置"""
        import random
        s_a = ''.join(random.choices('0123456789', k=8))
        s_b = ''.join(random.choices('0123456789', k=8))
        s_c = ''.join(random.choices('0123456789', k=8))

        # 注册C（无关用户）
        await client.post("/api/v1/auth/register", json={"phone": f"138{s_c}", "password": "testpass"})
        r = await client.post("/api/v1/auth/login", json={"phone": f"138{s_c}", "password": "testpass"})
        tc = r.json()["data"]["access_token"]

        # A和B建立关系
        await client.post("/api/v1/auth/register", json={"phone": f"138{s_a}", "password": "testpass"})
        await client.post("/api/v1/auth/register", json={"phone": f"138{s_b}", "password": "testpass"})
        r = await client.post("/api/v1/auth/login", json={"phone": f"138{s_a}", "password": "testpass"})
        ta = r.json()["data"]["access_token"]
        r = await client.post("/api/v1/auth/login", json={"phone": f"138{s_b}", "password": "testpass"})
        tb = r.json()["data"]["access_token"]

        client.headers["Authorization"] = f"Bearer {ta}"
        inv = await client.post("/api/v1/relationships/invite", json={"type": "friend"})
        code = inv.json()["data"]["invite_code"]
        rel_id = inv.json()["data"]["id"]

        client.headers["Authorization"] = f"Bearer {tb}"
        await client.post("/api/v1/relationships/join", json={"invite_code": code})

        # C尝试创建提醒配置
        client.headers["Authorization"] = f"Bearer {tc}"
        resp = await client.post(
            f"/api/v1/relationships/{rel_id}/reminders",
            json={"category": "weather", "enabled": True, "config": {}},
        )
        assert resp.json()["code"] != 0


@pytest.mark.asyncio
class TestReminderSendConfirm:
    """提醒发送和确认流程测试"""

    async def test_send_and_confirm(self, client: AsyncClient):
        """A发送提醒 → B确认 → 查看历史"""
        ta, tb, uid_a, rel_id = await _create_relationship(client)

        # A创建提醒配置
        client.headers["Authorization"] = f"Bearer {ta}"
        create = await client.post(
            f"/api/v1/relationships/{rel_id}/reminders",
            json={"category": "weather", "enabled": True, "config": {}},
        )
        config_id = create.json()["data"]["id"]

        # A发送提醒
        send = await client.post(
            f"/api/v1/reminders/{config_id}/send",
            json={"message": "记得带伞哦 🌂"},
        )
        assert send.status_code == 200
        log_data = send.json()["data"]
        log_id = log_data["id"]
        assert log_data["status"] == "sent"

        # B确认收到
        client.headers["Authorization"] = f"Bearer {tb}"
        confirm = await client.post(f"/api/v1/reminders/{log_id}/confirm")
        assert confirm.status_code == 200
        assert confirm.json()["data"]["status"] == "confirmed"

        # 查看提醒历史
        logs = await client.get(f"/api/v1/reminders/{config_id}/logs")
        assert len(logs.json()["data"]) >= 1

    async def test_cannot_confirm_twice(self, client: AsyncClient):
        """不能重复确认"""
        ta, tb, uid_a, rel_id = await _create_relationship(client)

        client.headers["Authorization"] = f"Bearer {ta}"
        create = await client.post(
            f"/api/v1/relationships/{rel_id}/reminders",
            json={"category": "weather", "enabled": True, "config": {}},
        )
        config_id = create.json()["data"]["id"]

        send = await client.post(
            f"/api/v1/reminders/{config_id}/send",
            json={"message": "测试"},
        )
        log_id = send.json()["data"]["id"]

        client.headers["Authorization"] = f"Bearer {tb}"
        await client.post(f"/api/v1/reminders/{log_id}/confirm")
        dup = await client.post(f"/api/v1/reminders/{log_id}/confirm")
        assert dup.json()["code"] != 0


@pytest.mark.asyncio
class TestReminderStats:
    """提醒统计测试"""

    async def test_stats_returns_valid_data(self, auth_client: AsyncClient):
        """统计接口返回正确结构"""
        resp = await auth_client.get("/api/v1/reminders/stats")
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert "total_sent" in data
        assert "total_received" in data
        assert "active_streak_days" in data
        assert "by_category" in data
