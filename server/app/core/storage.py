"""对象存储服务 — MinIO / OSS 兼容"""

import logging
import uuid
from io import BytesIO

from minio import Minio
from minio.error import S3Error

from app.common.exceptions import SystemException
from app.core.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)

ALLOWED_IMAGE_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
MAX_AVATAR_SIZE = 2 * 1024 * 1024  # 2MB


class StorageService:
    """MinIO 对象存储服务"""

    _client: Minio | None = None

    @classmethod
    def _get_client(cls) -> Minio | None:
        """延迟初始化 MinIO 客户端"""
        if cls._client is not None:
            return cls._client
        if not settings.MINIO_ENDPOINT:
            logger.warning("MinIO not configured, storage disabled")
            return None
        try:
            client = Minio(
                endpoint=settings.MINIO_ENDPOINT,
                access_key=settings.MINIO_ACCESS_KEY,
                secret_key=settings.MINIO_SECRET_KEY,
                secure=False,
            )
            # Ensure bucket exists
            if not client.bucket_exists(settings.MINIO_BUCKET):
                client.make_bucket(settings.MINIO_BUCKET)
                logger.info(f"Created bucket: {settings.MINIO_BUCKET}")
            cls._client = client
            return client
        except Exception as e:
            cls._client = None  # Don't cache failures
            logger.warning(f"MinIO连接失败: {e}")
            return None

    @classmethod
    async def upload_avatar(cls, file_content: bytes, content_type: str) -> str:
        """
        上传头像图片

        Returns:
            头像的访问URL
        """
        if content_type not in ALLOWED_IMAGE_TYPES:
            raise ValueError(f"不支持的文件类型: {content_type}，仅支持 JPEG/PNG/WebP")

        if len(file_content) > MAX_AVATAR_SIZE:
            raise ValueError(f"文件过大，最大 {MAX_AVATAR_SIZE // 1024 // 1024}MB")

        ext = ALLOWED_IMAGE_TYPES[content_type]
        object_name = f"avatars/{uuid.uuid4().hex}.{ext}"

        client = cls._get_client()
        if not client:
            raise SystemException(
                code=SystemException.EXTERNAL_SERVICE_ERROR,
                message="对象存储服务不可用",
                status_code=503,
            )

        try:
            client.put_object(
                bucket_name=settings.MINIO_BUCKET,
                object_name=object_name,
                data=BytesIO(file_content),
                length=len(file_content),
                content_type=content_type,
            )
            url = f"http://{settings.MINIO_ENDPOINT}/{settings.MINIO_BUCKET}/{object_name}"
            logger.info(f"Avatar uploaded: {object_name}")
            return url
        except S3Error as e:
            logger.error(f"上传失败: {e}")
            raise SystemException(
                code=SystemException.EXTERNAL_SERVICE_ERROR,
                message="文件上传失败",
                status_code=503,
            )

    @classmethod
    async def delete_avatar(cls, url: str) -> None:
        """删除旧头像"""
        if not url or not settings.MINIO_ENDPOINT:
            return
        client = cls._get_client()
        if not client:
            return
        try:
            prefix = f"http://{settings.MINIO_ENDPOINT}/{settings.MINIO_BUCKET}/"
            if url.startswith(prefix):
                object_name = url[len(prefix):]
                client.remove_object(settings.MINIO_BUCKET, object_name)
                logger.debug(f"Deleted: {object_name}")
        except S3Error:
            pass  # 旧文件可能已不存在
