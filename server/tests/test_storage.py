"""
对象存储 & 头像上传 — 单元测试
"""

import io

import pytest
from app.common.exceptions import SystemException


@pytest.mark.asyncio
class TestStorageValidation:
    """存储服务参数验证测试"""

    async def test_reject_invalid_content_type(self):
        """拒绝不支持的文件类型"""
        from app.core.storage import StorageService
        with pytest.raises(ValueError, match="不支持的文件类型"):
            await StorageService.upload_avatar(b"fake", "image/gif")

    async def test_reject_oversize_file(self):
        """拒绝超大文件"""
        from app.core.storage import StorageService
        big = b"x" * (3 * 1024 * 1024)  # 3MB
        with pytest.raises(ValueError, match="文件过大"):
            await StorageService.upload_avatar(big, "image/jpeg")

    async def test_storage_unavailable_when_not_configured(self):
        """MinIO未配置时抛出错误"""
        from app.core.storage import StorageService
        StorageService._client = None  # Reset
        import app.core.storage as s
        old = s.settings.MINIO_ENDPOINT
        s.settings.MINIO_ENDPOINT = ""
        try:
            with pytest.raises(SystemException):
                await StorageService.upload_avatar(b"valid", "image/png")
        finally:
            s.settings.MINIO_ENDPOINT = old
            StorageService._client = None


@pytest.mark.asyncio
class TestAvatarEndpoint:
    """头像端点测试"""

    async def test_upload_without_auth(self, client):
        """未认证上传被拒绝"""
        resp = await client.post("/api/v1/users/me/avatar")
        assert resp.status_code == 401

    async def test_delete_without_auth(self, client):
        """未认证删除被拒绝"""
        resp = await client.delete("/api/v1/users/me/avatar")
        assert resp.status_code == 401

    async def test_upload_no_file_returns_422(self, auth_client):
        """不上传文件返回422"""
        resp = await auth_client.post("/api/v1/users/me/avatar")
        assert resp.status_code == 422

    async def test_upload_minio_unavailable(self, auth_client):
        """MinIO不可用时返回错误"""
        import app.core.storage as s
        old = s.settings.MINIO_ENDPOINT
        s.settings.MINIO_ENDPOINT = ""
        s.StorageService._client = None
        try:
            resp = await auth_client.post(
                "/api/v1/users/me/avatar",
                files={"file": ("test.png", io.BytesIO(b"fake-image"), "image/png")},
            )
            assert resp.status_code == 503
        finally:
            s.settings.MINIO_ENDPOINT = old
            s.StorageService._client = None
