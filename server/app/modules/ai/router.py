"""
AI 模块 — API 路由

提供 AI 关怀建议和对话交互接口。
"""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.common.response import success_response
from app.core.dependencies import get_current_active_user
from app.modules.ai.schemas import ChatRequest, SuggestRequest
from app.modules.ai.service import AIService
from app.modules.users.models import User

router = APIRouter(prefix="/ai", tags=["AI"])


@router.post("/suggest", summary="AI 生成关怀建议")
async def get_suggestion(
    data: SuggestRequest,
    current_user: Annotated[User, Depends(get_current_active_user)],
):
    """
    根据场景生成 AI 关怀建议

    支持场景: weather（天气）, sleep（睡觉）, meal（吃饭）, custom（自定义）
    """
    result = await AIService.generate_suggestion(data)
    return success_response(data=result.model_dump())


@router.post("/chat", summary="AI 对话交互")
async def chat_with_ai(
    data: ChatRequest,
    current_user: Annotated[User, Depends(get_current_active_user)],
):
    """
    与 AI 关怀助手对话

    支持上下文对话，history 中传入之前的对话记录。
    """
    result = await AIService.chat(data)
    return success_response(data=result.model_dump())
