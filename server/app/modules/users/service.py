"""
用户模块 — 业务逻辑服务层
"""

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.exceptions import UserException
from app.modules.users.models import Device, User, UserLocation
from app.modules.users.schemas import DeviceRegister, LocationUpdate, UserUpdate


class UserService:
    """用户业务逻辑服务"""

    @staticmethod
    async def get_user_by_id(db: AsyncSession, user_id: uuid.UUID) -> User:
        """
        根据 ID 获取用户

        Raises:
            UserException: 用户不存在
        """
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user:
            raise UserException(
                code=UserException.NOT_FOUND,
                message="用户不存在",
                status_code=404,
            )
        return user

    @staticmethod
    async def get_user_by_phone(db: AsyncSession, phone: str) -> User | None:
        """根据手机号查找用户（可能不存在）"""
        result = await db.execute(select(User).where(User.phone == phone))
        return result.scalar_one_or_none()

    @staticmethod
    async def update_user(db: AsyncSession, user: User, data: UserUpdate) -> User:
        """
        更新用户信息

        仅更新请求中非 None 的字段。
        """
        update_data = data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(user, field, value)
        await db.flush()
        await db.refresh(user)
        return user

    @staticmethod
    async def update_location(
        db: AsyncSession,
        user_id: uuid.UUID,
        data: LocationUpdate,
    ) -> UserLocation:
        """
        更新用户位置（upsert 语义：不存在则创建，存在则更新）
        """
        result = await db.execute(
            select(UserLocation).where(UserLocation.user_id == user_id)
        )
        location = result.scalar_one_or_none()

        if location:
            # 更新
            for field, value in data.model_dump().items():
                setattr(location, field, value)
        else:
            # 创建
            location = UserLocation(user_id=user_id, **data.model_dump())
            db.add(location)

        await db.flush()
        await db.refresh(location)
        return location

    @staticmethod
    async def register_device(
        db: AsyncSession,
        user_id: uuid.UUID,
        data: DeviceRegister,
    ) -> Device:
        """
        注册用户设备（存储 FCM Token）

        如果相同 FCM Token 已存在，则更新关联的用户。
        """
        # 检查是否已存在相同 Token
        result = await db.execute(
            select(Device).where(Device.fcm_token == data.fcm_token)
        )
        device = result.scalar_one_or_none()

        if device:
            # Token 已存在，更新用户关联
            device.user_id = user_id
            device.device_info = data.device_info
        else:
            # 新设备注册
            device = Device(
                user_id=user_id,
                fcm_token=data.fcm_token,
                device_info=data.device_info,
            )
            db.add(device)

        await db.flush()
        await db.refresh(device)
        return device
