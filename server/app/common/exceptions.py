"""
自定义异常体系模块

错误码规范:
- 1xxx: 认证相关
- 2xxx: 用户相关
- 3xxx: 关系相关
- 4xxx: 提醒相关
- 5xxx: 系统相关
"""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


class AppException(Exception):
    """应用异常基类"""

    def __init__(
        self,
        code: int,
        message: str,
        status_code: int = 400,
    ):
        self.code = code
        self.message = message
        self.status_code = status_code
        super().__init__(message)


# ==================== 认证异常 (1xxx) ====================

class AuthException(AppException):
    """认证相关异常"""

    # 预定义错误码
    INVALID_CREDENTIALS = 1001
    TOKEN_EXPIRED = 1002
    TOKEN_INVALID = 1003
    USER_EXISTS = 1004
    INVALID_REFRESH_TOKEN = 1005

    def __init__(self, code: int = 1000, message: str = "认证失败", status_code: int = 401):
        super().__init__(code=code, message=message, status_code=status_code)


# ==================== 用户异常 (2xxx) ====================

class UserException(AppException):
    """用户相关异常"""

    NOT_FOUND = 2001
    PROFILE_UPDATE_FAILED = 2002
    LOCATION_UPDATE_FAILED = 2003

    def __init__(self, code: int = 2000, message: str = "用户操作失败", status_code: int = 400):
        super().__init__(code=code, message=message, status_code=status_code)


# ==================== 关系异常 (3xxx) ====================

class RelationshipException(AppException):
    """关系相关异常"""

    NOT_FOUND = 3001
    ALREADY_EXISTS = 3002
    INVITE_EXPIRED = 3003
    INVITE_INVALID = 3004
    CANNOT_INVITE_SELF = 3005
    ALREADY_PAIRED = 3006

    def __init__(self, code: int = 3000, message: str = "关系操作失败", status_code: int = 400):
        super().__init__(code=code, message=message, status_code=status_code)


# ==================== 提醒异常 (4xxx) ====================

class ReminderException(AppException):
    """提醒相关异常"""

    NOT_FOUND = 4001
    CONFIG_INVALID = 4002
    SEND_FAILED = 4003
    ALREADY_CONFIRMED = 4004

    def __init__(self, code: int = 4000, message: str = "提醒操作失败", status_code: int = 400):
        super().__init__(code=code, message=message, status_code=status_code)


# ==================== 系统异常 (5xxx) ====================

class SystemException(AppException):
    """系统相关异常"""

    INTERNAL_ERROR = 5001
    EXTERNAL_SERVICE_ERROR = 5002
    REDIS_ERROR = 5003
    DATABASE_ERROR = 5004

    def __init__(self, code: int = 5000, message: str = "系统错误", status_code: int = 500):
        super().__init__(code=code, message=message, status_code=status_code)


# ==================== 全局异常处理器 ====================

def register_exception_handlers(app: FastAPI) -> None:
    """
    注册全局异常处理器到 FastAPI 应用

    Args:
        app: FastAPI 应用实例
    """

    @app.exception_handler(AppException)
    async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
        """处理所有自定义应用异常"""
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "code": exc.code,
                "message": exc.message,
                "data": None,
            },
        )

    @app.exception_handler(Exception)
    async def general_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        """处理所有未捕获的异常"""
        return JSONResponse(
            status_code=500,
            content={
                "code": 5001,
                "message": "服务器内部错误",
                "data": None,
            },
        )
