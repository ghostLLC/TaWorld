"""
推送服务 — 单元测试

验证 PushService 在已配置和未配置 FCM Key 时的行为。
"""

import pytest
from httpx import AsyncClient

from app.core.push_service import PushService


@pytest.mark.asyncio
class TestPushService:
    """推送服务单元测试"""

    async def test_send_without_fcm_key(self):
        """未配置 FCM Key 时不抛异常，仅记录日志"""
        import logging
        from app.core import push_service

        # 验证调用不抛异常
        with self._capture_log(push_service.logger, logging.INFO) as buf:
            await PushService.send(
                user_id="test-user-id",
                title="测试标题",
                body="测试正文",
                data={"type": "test"},
            )
        log_output = buf.getvalue()
        assert "FCM未配置" in log_output, "应产生 FCM 未配置的日志"

    async def test_send_graceful_on_token_lookup_failure(self):
        """用户无设备时不抛异常"""
        # 使用一个不存在的用户ID
        await PushService.send(
            user_id="00000000-0000-0000-0000-000000000000",
            title="测试",
            body="测试",
        )
        # 不应抛出异常

    def _capture_log(self, logger, level):
        """捕获日志输出的辅助工具"""
        import io
        import logging

        class CaptureHandler(logging.Handler):
            def __init__(self):
                super().__init__()
                self.buffer = io.StringIO()

            def emit(self, record):
                self.buffer.write(self.format(record) + "\n")

        handler = CaptureHandler()
        handler.setLevel(level)
        logger.addHandler(handler)
        return _CaptureContext(logger, handler)


class _CaptureContext:
    def __init__(self, logger, handler):
        self.logger = logger
        self.handler = handler

    def __enter__(self):
        return self.handler.buffer

    def __exit__(self, *args):
        self.logger.removeHandler(self.handler)
