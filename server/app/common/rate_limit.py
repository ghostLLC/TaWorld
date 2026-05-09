"""
简易频率限制中间件

基于内存的滑动窗口限流，适用于单机部署。
"""

import time
from collections import defaultdict

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse


class RateLimiter:
    """滑动窗口限流器"""

    def __init__(self, max_requests: int = 10, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._buckets: dict[str, list[float]] = defaultdict(list)

    def is_allowed(self, key: str) -> bool:
        now = time.time()
        window_start = now - self.window_seconds
        self._buckets[key] = [t for t in self._buckets[key] if t > window_start]
        if len(self._buckets[key]) >= self.max_requests:
            return False
        self._buckets[key].append(now)
        return True


class RateLimitMiddleware(BaseHTTPMiddleware):
    """FastAPI 频率限制中间件"""

    # 需要限流的路径前缀
    RATE_LIMITED_PREFIXES = {
        "/api/v1/auth": RateLimiter(max_requests=10, window_seconds=60),
    }

    async def dispatch(self, request: Request, call_next):
        client_ip = request.client.host if request.client else "unknown"

        # 跳过本地请求（开发/测试环境）
        if client_ip in ("127.0.0.1", "localhost", "::1"):
            return await call_next(request)

        for prefix, limiter in self.RATE_LIMITED_PREFIXES.items():
            if request.url.path.startswith(prefix):
                if not limiter.is_allowed(client_ip):
                    return JSONResponse(
                        status_code=429,
                        content={
                            "code": 5002,
                            "message": "请求过于频繁，请稍后再试",
                            "data": None,
                        },
                    )
                break

        return await call_next(request)
