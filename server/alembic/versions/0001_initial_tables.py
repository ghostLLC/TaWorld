"""initial tables

Revision ID: 0001
Revises:
Create Date: 2026-05-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers
revision: str = '0001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _create_enum_safe(name: str, values: list[str]) -> None:
    """Safely create a PostgreSQL enum type, ignoring if already exists."""
    try:
        bind = op.get_bind()
        enum_type = postgresql.ENUM(*values, name=name, create_type=True)
        enum_type.create(bind, checkfirst=True)
    except Exception:
        pass  # type already exists


def upgrade() -> None:
    # ---- Enum types ----
    _create_enum_safe('relationshiptype', ['couple', 'family', 'friend'])
    _create_enum_safe('relationshipstatus', ['pending', 'active', 'dissolved'])
    _create_enum_safe('remindercategory', ['weather', 'sleep', 'meal', 'custom'])
    _create_enum_safe('reminderlogstatus', ['triggered', 'sent', 'confirmed'])

    # ---- users ----
    op.create_table(
        'users',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('phone', sa.String(20), unique=True, index=True, nullable=False),
        sa.Column('nickname', sa.String(50), nullable=False, server_default=''),
        sa.Column('avatar_url', sa.String(500), nullable=True),
        sa.Column('password_hash', sa.String(200), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ---- user_locations ----
    op.create_table(
        'user_locations',
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('latitude', sa.Float(), nullable=False),
        sa.Column('longitude', sa.Float(), nullable=False),
        sa.Column('city', sa.String(100), nullable=True),
        sa.Column('district', sa.String(100), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ---- devices ----
    op.create_table(
        'devices',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('fcm_token', sa.String(500), nullable=False),
        sa.Column('device_info', sa.String(500), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ---- relationships ----
    op.create_table(
        'relationships',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_a_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_b_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=True),
        sa.Column('type', postgresql.ENUM('couple', 'family', 'friend', name='relationshiptype', create_type=False), nullable=False, server_default='couple'),
        sa.Column('status', postgresql.ENUM('pending', 'active', 'dissolved', name='relationshipstatus', create_type=False), nullable=False, server_default='pending'),
        sa.Column('invite_code', sa.String(20), unique=True, index=True, nullable=False),
        sa.Column('nickname_a_for_b', sa.String(50), nullable=True),
        sa.Column('nickname_b_for_a', sa.String(50), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ---- reminder_configs ----
    op.create_table(
        'reminder_configs',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('relationship_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('relationships.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('category', postgresql.ENUM('weather', 'sleep', 'meal', 'custom', name='remindercategory', create_type=False), nullable=False),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('config', postgresql.JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column('created_by', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ---- reminder_logs ----
    op.create_table(
        'reminder_logs',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('config_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('reminder_configs.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('sender_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('receiver_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('message', sa.Text(), nullable=True),
        sa.Column('status', postgresql.ENUM('triggered', 'sent', 'confirmed', name='reminderlogstatus', create_type=False), nullable=False, server_default='triggered'),
        sa.Column('triggered_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('sent_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('confirmed_at', sa.DateTime(timezone=True), nullable=True),
    )

    # ---- achievements ----
    op.create_table(
        'achievements',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(100), unique=True, nullable=False),
        sa.Column('description', sa.String(500), nullable=False, server_default=''),
        sa.Column('icon', sa.String(50), nullable=False, server_default='🏆'),
        sa.Column('category', sa.String(50), nullable=False, server_default='general'),
        sa.Column('unlock_condition', postgresql.JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column('points', sa.Integer(), nullable=False, server_default=sa.text('0')),
    )

    # ---- user_achievements ----
    op.create_table(
        'user_achievements',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('achievement_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('achievements.id', ondelete='CASCADE'), nullable=False),
        sa.Column('progress', sa.Integer(), nullable=False, server_default=sa.text('0')),
        sa.Column('unlocked', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('unlocked_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_table('user_achievements')
    op.drop_table('achievements')
    op.drop_table('reminder_logs')
    op.drop_table('reminder_configs')
    op.drop_table('relationships')
    op.drop_table('devices')
    op.drop_table('user_locations')
    op.drop_table('users')

    for name in ['reminderlogstatus', 'remindercategory', 'relationshipstatus', 'relationshiptype']:
        postgresql.ENUM(name=name).drop(op.get_bind(), checkfirst=True)
