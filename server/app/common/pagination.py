"""
分页工具模块

提供统一的分页参数和分页查询工具。
"""

from typing import Annotated, TypeVar

from fastapi import Query
from pydantic import BaseModel
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

T = TypeVar("T")


class PaginationParams(BaseModel):
    """分页参数"""
    page: int = 1
    page_size: int = 20

    @property
    def offset(self) -> int:
        """计算偏移量"""
        return (self.page - 1) * self.page_size


def get_pagination(
    page: Annotated[int, Query(ge=1, description="页码，从1开始")] = 1,
    page_size: Annotated[int, Query(ge=1, le=100, description="每页数量，最大100")] = 20,
) -> PaginationParams:
    """
    FastAPI 依赖注入：获取分页参数

    Usage:
        @router.get("/list")
        async def list_items(pagination: PaginationParams = Depends(get_pagination)):
            ...
    """
    return PaginationParams(page=page, page_size=page_size)


async def paginate(
    db: AsyncSession,
    query: Select,
    pagination: PaginationParams,
) -> tuple[list, int]:
    """
    执行分页查询

    Args:
        db: 数据库 Session
        query: SQLAlchemy Select 查询
        pagination: 分页参数

    Returns:
        (items, total) 元组：当前页数据列表和总记录数
    """
    # 查询总数
    count_query = select(func.count()).select_from(query.subquery())
    total_result = await db.execute(count_query)
    total = total_result.scalar() or 0

    # 查询当前页数据
    paginated_query = query.offset(pagination.offset).limit(pagination.page_size)
    result = await db.execute(paginated_query)
    items = list(result.scalars().all())

    return items, total
