"""
FCM推送通知服务

支持Firebase Cloud Messaging推送，未配置时优雅降级为日志记录。
"""

import logging
from typing import Any

import httpx

from app.core.config import get_settings
from app.core.database import async_session_factory

settings = get_settings()
logger = logging.getLogger(__name__)

FCM_LEGACY_URL = "https://fcm.googleapis.com/fcm/send"


class PushService:
    """FCM推送通知服务"""

    @staticmethod
    async def send(
        user_id: str,
        title: str,
        body: str,
        data: dict[str, Any] | None = None,
    ) -> None:
        """
        向指定用户的所有设备发送推送通知

        Args:
            user_id: 用户UUID字符串
            title: 通知标题
            body: 通知正文
            data: 附加数据payload

        如果FCM_SERVER_KEY未配置，仅记录日志（优雅降级）。
        推送失败不会阻塞业务流程。
        """
        if not settings.FCM_SERVER_KEY:
            logger.info(
                f"FCM未配置 | 目标用户={user_id} | "
                f"title={title} | body={body}"
            )
            return

        try:
            tokens = await PushService._get_user_fcm_tokens(user_id)
            if not tokens:
                logger.debug(f"用户 {user_id} 无已注册设备")
                return

            headers = {
                "Authorization": f"key={settings.FCM_SERVER_KEY}",
                "Content-Type": "application/json",
            }

            payload: dict[str, Any] = {
                "notification": {
                    "title": title,
                    "body": body,
                },
            }
            if data:
                payload["data"] = {k: str(v) for k, v in data.items()}

            async with httpx.AsyncClient(timeout=10) as client:
                for token in tokens:
                    try:
                        payload["to"] = token
                        response = await client.post(
                            FCM_LEGACY_URL,
                            json=payload,
                            headers=headers,
                        )
                        result = response.json()
                        if result.get("failure", 0) > 0:
                            logger.warning(
                                f"FCM推送失败 | token={token[:20]}... | "
                                f"error={result.get('results', [{}])[0].get('error')}"
                            )
                        else:
                            logger.debug(f"FCM推送成功 | user={user_id}")
                    except Exception:
                        logger.warning(f"FCM推送异常 | token={token[:20]}...")

        except Exception:
            logger.warning(f"推送通知发送失败 | user={user_id}", exc_info=True)

    @staticmethod
    async def _get_user_fcm_tokens(user_id: str) -> list[str]:
        """查询用户已注册的FCM Token列表"""
        from sqlalchemy import select

        from app.modules.users.models import Device

        async with async_session_factory() as db:
            result = await db.execute(
                select(Device.fcm_token).where(Device.user_id == user_id)
            )
            return [row[0] for row in result.all()]
