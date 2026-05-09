"""
统一响应格式模块

所有 API 响应遵循统一格式:
{
    "code": 0,          # 0=成功, 非0=错误码
    "message": "success",
    "data": {}           # 响应数据
}
"""

from typing import Any

from pydantic import BaseModel


class ApiResponse(BaseModel):
    """统一 API 响应模型"""
    code: int = 0
    message: str = "success"
    data: Any = None


class PaginatedData(BaseModel):
    """分页数据包装"""
    items: list[Any]
    total: int
    page: int
    page_size: int
    total_pages: int


def success_response(
    data: Any = None,
    message: str = "success",
) -> dict[str, Any]:
    """
    构建成功响应

    Args:
        data: 响应数据
        message: 成功消息

    Returns:
        统一格式的响应字典
    """
    return {
        "code": 0,
        "message": message,
        "data": data,
    }


def error_response(
    code: int,
    message: str,
    data: Any = None,
) -> dict[str, Any]:
    """
    构建错误响应

    Args:
        code: 错误码（非0）
        message: 错误消息
        data: 附加数据（可选）

    Returns:
        统一格式的错误响应字典
    """
    return {
        "code": code,
        "message": message,
        "data": data,
    }


def paginated_response(
    items: list[Any],
    total: int,
    page: int,
    page_size: int,
) -> dict[str, Any]:
    """
    构建分页响应

    Args:
        items: 当前页数据列表
        total: 总记录数
        page: 当前页码
        page_size: 每页大小

    Returns:
        包含分页信息的成功响应
    """
    total_pages = (total + page_size - 1) // page_size if page_size > 0 else 0
    return success_response(
        data={
            "items": items,
            "total": total,
            "page": page,
            "page_size": page_size,
            "total_pages": total_pages,
        }
    )
