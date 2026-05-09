"""
关系模块 — 集成测试

覆盖邀请、加入、查询、更新、解除的完整流程。
"""

import uuid

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
class TestRelationshipFlow:
    """关系完整流程测试"""

    async def test_invite_and_join_flow(self, client: AsyncClient):
        """两人建立关系：A邀请 → B加入 → 验证关系生效"""
        import random

        # 注册用户A和B
        suffix_a = ''.join(random.choices('0123456789', k=8))
        suffix_b = ''.join(random.choices('0123456789', k=8))

        # 注册A
        await client.post("/api/v1/auth/register", json={
            "phone": f"138{suffix_a}",
            "password": "test123456",
        })
        resp_a = await client.post("/api/v1/auth/login", json={
            "phone": f"138{suffix_a}",
            "password": "test123456",
        })
        token_a = resp_a.json()["data"]["access_token"]

        # 注册B
        await client.post("/api/v1/auth/register", json={
            "phone": f"138{suffix_b}",
            "password": "test123456",
        })
        resp_b = await client.post("/api/v1/auth/login", json={
            "phone": f"138{suffix_b}",
            "password": "test123456",
        })
        token_b = resp_b.json()["data"]["access_token"]

        # A创建邀请
        client.headers["Authorization"] = f"Bearer {token_a}"
        invite_resp = await client.post("/api/v1/relationships/invite", json={
            "type": "friend",
        })
        assert invite_resp.status_code == 200
        invite_data = invite_resp.json()["data"]
        invite_code = invite_data["invite_code"]
        assert len(invite_code) == 8

        # B加入
        client.headers["Authorization"] = f"Bearer {token_b}"
        join_resp = await client.post("/api/v1/relationships/join", json={
            "invite_code": invite_code,
        })
        assert join_resp.status_code == 200
        assert join_resp.json()["data"]["status"] == "active"

        # A查看关系列表
        client.headers["Authorization"] = f"Bearer {token_a}"
        list_resp = await client.get("/api/v1/relationships")
        assert list_resp.status_code == 200
        items = list_resp.json()["data"]
        assert len(items) >= 1
        rel = items[0]
        assert rel["status"] == "active"
        assert rel["partner_id"] is not None
        assert rel["partner_nickname"] is not None

    async def test_invite_self_join_rejected(self, client: AsyncClient):
        """不能自己加入自己的邀请"""
        import random
        suffix = ''.join(random.choices('0123456789', k=8))
        phone = f"138{suffix}"

        await client.post("/api/v1/auth/register", json={
            "phone": phone, "password": "test123456",
        })
        resp = await client.post("/api/v1/auth/login", json={
            "phone": phone, "password": "test123456",
        })
        token = resp.json()["data"]["access_token"]
        client.headers["Authorization"] = f"Bearer {token}"

        invite = await client.post("/api/v1/relationships/invite", json={"type": "couple"})
        code = invite.json()["data"]["invite_code"]

        join = await client.post("/api/v1/relationships/join", json={"invite_code": code})
        assert join.json()["code"] != 0

    async def test_invalid_invite_code(self, auth_client: AsyncClient):
        """无效邀请码返回错误"""
        resp = await auth_client.post("/api/v1/relationships/join", json={
            "invite_code": "INVALID1",
        })
        assert resp.json()["code"] != 0

    async def test_dissolve_relationship(self, client: AsyncClient):
        """解除关系后列表不再包含活跃关系"""
        import random
        s_a = ''.join(random.choices('0123456789', k=8))
        s_b = ''.join(random.choices('0123456789', k=8))

        # 注册并建立关系
        await client.post("/api/v1/auth/register", json={"phone": f"138{s_a}", "password": "testpass"})
        r = await client.post("/api/v1/auth/login", json={"phone": f"138{s_a}", "password": "testpass"})
        ta = r.json()["data"]["access_token"]

        await client.post("/api/v1/auth/register", json={"phone": f"138{s_b}", "password": "testpass"})
        r = await client.post("/api/v1/auth/login", json={"phone": f"138{s_b}", "password": "testpass"})
        tb = r.json()["data"]["access_token"]

        client.headers["Authorization"] = f"Bearer {ta}"
        inv = await client.post("/api/v1/relationships/invite", json={"type": "friend"})
        code = inv.json()["data"]["invite_code"]

        client.headers["Authorization"] = f"Bearer {tb}"
        await client.post("/api/v1/relationships/join", json={"invite_code": code})

        # 获取关系
        client.headers["Authorization"] = f"Bearer {ta}"
        rels = await client.get("/api/v1/relationships")
        rel_id = rels.json()["data"][0]["id"]

        # 解除关系
        dissolve = await client.delete(f"/api/v1/relationships/{rel_id}")
        assert dissolve.status_code == 200
        assert dissolve.json()["code"] == 0

        # 验证状态
        rels_after = await client.get("/api/v1/relationships")
        items = [i for i in rels_after.json()["data"] if i["status"] == "active"]
        assert len(items) == 0


@pytest.mark.asyncio
class TestRelationshipUnauthorized:
    """未认证访问测试"""

    async def test_list_without_auth(self, client: AsyncClient):
        resp = await client.get("/api/v1/relationships")
        assert resp.status_code == 401

    async def test_invite_without_auth(self, client: AsyncClient):
        resp = await client.post("/api/v1/relationships/invite", json={"type": "couple"})
        assert resp.status_code == 401
