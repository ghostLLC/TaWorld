"""
AI 模块 — Pydantic Schemas
"""

from pydantic import BaseModel, Field


class SuggestRequest(BaseModel):
    """AI 关怀建议请求"""
    scene: str = Field(
        ...,
        description="场景: weather/sleep/meal/custom",
        examples=["weather"],
    )
    context: dict = Field(
        default_factory=dict,
        description="场景上下文信息",
        examples=[{"weather": "下雨", "partner_name": "小明"}],
    )


class SuggestResponse(BaseModel):
    """AI 关怀建议响应"""
    suggestion: str = Field(..., description="AI 生成的关怀建议")
    alternatives: list[str] = Field(
        default_factory=list,
        description="备选建议列表",
    )


class ChatRequest(BaseModel):
    """AI 对话请求"""
    message: str = Field(..., max_length=1000, description="用户消息")
    history: list[dict] = Field(
        default_factory=list,
        description="对话历史",
    )


class ChatResponse(BaseModel):
    """AI 对话响应"""
    reply: str = Field(..., description="AI 回复")
