"""
认证模块 — Pydantic Schemas
"""

from pydantic import BaseModel, Field


class RegisterRequest(BaseModel):
    """用户注册请求"""
    phone: str = Field(..., min_length=11, max_length=11, pattern=r"^1[3-9]\d{9}$", description="手机号")
    password: str = Field(..., min_length=6, max_length=50, description="密码")
    nickname: str = Field(default="", max_length=50, description="昵称（可选）")


class LoginRequest(BaseModel):
    """用户登录请求"""
    phone: str = Field(..., min_length=11, max_length=11, description="手机号")
    password: str = Field(..., min_length=6, max_length=50, description="密码")


class TokenResponse(BaseModel):
    """Token 响应"""
    access_token: str = Field(..., description="访问令牌")
    refresh_token: str = Field(..., description="刷新令牌")
    token_type: str = Field(default="bearer", description="令牌类型")


class RefreshRequest(BaseModel):
    """Token 刷新请求"""
    refresh_token: str = Field(..., description="刷新令牌")
