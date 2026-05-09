"""
AI 模块 — 业务逻辑服务层

封装 LLM API 调用，提供关怀建议生成和对话交互功能。
MVP 阶段实现层1（智能建议），使用 Prompt 模板 + LLM API。
"""

import logging
from typing import Any

import httpx

from app.core.config import get_settings
from app.modules.ai.schemas import ChatRequest, ChatResponse, SuggestRequest, SuggestResponse

settings = get_settings()
logger = logging.getLogger(__name__)

# ==================== Prompt 模板 ====================

SUGGEST_PROMPTS = {
    "weather": """你是一个温暖的关怀助手。用户想提醒Ta关心的人注意天气变化。
场景信息：{context}
请生成一条温暖、简短的关怀消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji。
输出格式（JSON）：
{{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}}""",

    "sleep": """你是一个温暖的关怀助手。用户想提醒Ta关心的人早点休息。
场景信息：{context}
请生成一条温暖的晚安提醒消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji，不要过于肉麻。
输出格式（JSON）：
{{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}}""",

    "meal": """你是一个温暖的关怀助手。用户想提醒Ta关心的人按时吃饭。
场景信息：{context}
请生成一条温暖的吃饭提醒消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji。
输出格式（JSON）：
{{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}}""",

    "custom": """你是一个温暖的关怀助手。用户想给Ta关心的人发送一条关怀消息。
场景信息：{context}
请生成一条温暖的关怀消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji。
输出格式（JSON）：
{{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}}""",
}

CHAT_SYSTEM_PROMPT = """你是「Ta的世界」APP的AI关怀助手。你的职责是：
1. 帮助用户更好地关心Ta在意的人
2. 提供关怀建议和温暖的表达方式
3. 回答关于APP功能的问题
4. 保持温暖、积极、有同理心的语气

注意事项：
- 回答要简洁，不超过200字
- 语气温暖自然，可以适当使用emoji
- 不要讨论与关怀无关的话题
- 保护用户隐私"""


class AIService:
    """AI 业务逻辑服务"""

    @staticmethod
    async def generate_suggestion(data: SuggestRequest) -> SuggestResponse:
        """
        生成关怀建议

        Args:
            data: 建议请求（场景 + 上下文）

        Returns:
            AI 生成的建议和备选项
        """
        prompt_template = SUGGEST_PROMPTS.get(data.scene, SUGGEST_PROMPTS["custom"])
        prompt = prompt_template.format(context=str(data.context))

        try:
            result = await AIService._call_llm(
                messages=[{"role": "user", "content": prompt}],
                temperature=0.8,
            )

            # 尝试解析 JSON 响应
            import json
            parsed = json.loads(result)
            return SuggestResponse(
                suggestion=parsed.get("suggestion", result),
                alternatives=parsed.get("alternatives", []),
            )
        except Exception as e:
            logger.warning(f"AI 建议生成失败，使用默认模板: {e}")
            return AIService._get_fallback_suggestion(data.scene, data.context)

    @staticmethod
    async def chat(data: ChatRequest) -> ChatResponse:
        """
        AI 对话交互

        Args:
            data: 对话请求（消息 + 历史）

        Returns:
            AI 回复
        """
        messages = [{"role": "system", "content": CHAT_SYSTEM_PROMPT}]

        # 添加对话历史
        for msg in data.history[-10:]:  # 保留最近10条历史
            messages.append(msg)

        messages.append({"role": "user", "content": data.message})

        try:
            reply = await AIService._call_llm(messages=messages, temperature=0.7)
            return ChatResponse(reply=reply)
        except Exception as e:
            logger.error(f"AI 对话失败: {e}")
            return ChatResponse(reply="抱歉，我暂时无法回应。请稍后再试 🙏")

    @staticmethod
    async def _call_llm(
        messages: list[dict[str, str]],
        temperature: float = 0.7,
        max_tokens: int = 500,
    ) -> str:
        """
        调用 LLM API

        支持 OpenAI 兼容接口（OpenAI / 通义千问等）。
        """
        if not settings.LLM_API_KEY:
            raise ValueError("LLM API Key 未配置")

        url = f"{settings.LLM_BASE_URL}/chat/completions"
        headers = {
            "Authorization": f"Bearer {settings.LLM_API_KEY}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": settings.LLM_MODEL,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }

        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            data = response.json()

        return data["choices"][0]["message"]["content"].strip()

    @staticmethod
    def _get_fallback_suggestion(scene: str, context: dict) -> SuggestResponse:
        """LLM 不可用时的降级方案：使用预设模板"""
        fallbacks = {
            "weather": SuggestResponse(
                suggestion="外面天气变化了，记得提醒Ta注意哦 ☁️",
                alternatives=[
                    "天气变了，关心一下Ta吧 🌤️",
                    "提醒Ta注意天气变化 🌂",
                ],
            ),
            "sleep": SuggestResponse(
                suggestion="夜深了，提醒Ta早点休息吧 🌙",
                alternatives=[
                    "该睡觉啦，提醒Ta放下手机 💤",
                    "晚安时间到，关心一下Ta吧 ✨",
                ],
            ),
            "meal": SuggestResponse(
                suggestion="到饭点啦，提醒Ta按时吃饭 🍚",
                alternatives=[
                    "别让Ta饿肚子，提醒Ta吃饭吧 🥗",
                    "吃饭时间到，关心一下Ta 🍜",
                ],
            ),
            "custom": SuggestResponse(
                suggestion="想Ta了就告诉Ta吧 💝",
                alternatives=[
                    "简单的关心，也是最好的温暖 ☀️",
                    "发条消息，让Ta知道你在想Ta 💌",
                ],
            ),
        }
        return fallbacks.get(scene, fallbacks["custom"])
