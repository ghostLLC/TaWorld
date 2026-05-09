# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Activate virtual environment (Windows)
server\venv\Scripts\activate

# Run dev server (from server/)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Run tests (from server/)
pytest                                    # all tests
pytest tests/test_auth.py                 # single file
pytest tests/test_auth.py -k test_login   # specific test

# Database migrations (from server/)
alembic revision --autogenerate -m "description"   # generate
alembic upgrade head                                # apply
alembic downgrade -1                                # rollback

# Infrastructure (from repo root)
docker-compose up -d postgres redis       # just DB + cache
docker-compose up -d                      # full stack
```

## Architecture

**Modular Monolith.** The single FastAPI app (`server/app/main.py`) registers 7 business modules under `/api/v1`. Each module follows a strict 4-layer dependency order:

```
models.py  →  schemas.py  →  service.py  →  router.py
  (DB)         (validation)    (logic)        (HTTP)
```

Modules are in `server/app/modules/`: `auth`, `users`, `relationships`, `reminders`, `weather`, `achievements`, `ai`.

**Core layer** (`server/app/core/`): config, database engine/session/mixins, JWT/password security, and FastAPI dependencies (`get_current_user`, `get_current_active_user`, `get_redis`).

**Common layer** (`server/app/common/`): unified response helpers, custom exception hierarchy with error codes, and pagination utility.

**Tasks** (`server/app/tasks/`): APScheduler jobs — weather check runs hourly, timed reminder check runs every minute. Scheduler starts/stops in the FastAPI `lifespan`.

## Key Conventions

### Response format
All endpoints must return `{code, message, data}` via helpers in `app/common/response.py`. Never return raw dicts.

### Error handling
Use custom exceptions from `app/common/exceptions.py`, never `raise HTTPException` directly. Each module has its own exception class with predefined error codes:
- `1xxx` AuthException
- `2xxx` UserException
- `3xxx` RelationshipException
- `4xxx` ReminderException
- `5xxx` SystemException

The global exception handler in `exceptions.py` catches `AppException` and converts it to the unified response format.

### Authentication
Protected routes use `current_user: Annotated[User, Depends(get_current_active_user)]`. The `get_current_user` dependency validates the JWT and fetches the User from DB. `get_current_active_user` wraps it (extension point for user-status checks).

### Database session
`get_db()` is an async generator dependency — it auto-commits on success and auto-rollbacks on exception. No need for explicit `await db.commit()` in services called from routes. However, scheduled tasks that create their own sessions via `async_session_factory()` must commit/rollback manually.

### Models
Use `Base, UUIDMixin, TimestampMixin` from `app/core/database.py`. UUIDMixin provides `id: UUID` PK. TimestampMixin provides `created_at`/`updated_at` (auto-maintained by the DB).

## Gotchas

- **Tests use SQLite** (`sqlite+aiosqlite:///./test.db`) not PostgreSQL. The `auth_client` fixture registers a new user on every call — tests sharing the same phone number will fail with duplicate errors.
- **Weather module has no DB models** — all weather data is cached in Redis (TTL 30 min). The module only has `schemas.py`, `service.py`, `router.py`.
- **Reminder direction**: the system reminds user A to care about user B. In `weather_check.py`, the `receiver_id` on the log is set to `user_a_id` (the person receiving the nudge to care). `send_reminder` marks A→B communication; `confirm_reminder` is B acknowledging.
- **JSONB flexibility**: `reminder_configs.config` and `achievements.unlock_condition` are JSONB. The reminder config structure differs by category (weather vs sleep vs meal vs custom). See `docs/architecture.md` for examples.
- **Enum types**: `RelationshipType`, `RelationshipStatus`, `ReminderCategory`, `ReminderLogStatus` are PostgreSQL native enums (not varchar). Alembic must detect these.
- **No migration files yet**: `alembic/versions/` is empty. First `alembic revision --autogenerate` will generate the initial schema.

## TODO Hotspots

These are the marked `# TODO` items in the codebase that need implementation:

| Priority | Location | What |
|----------|----------|------|
| P0 | `reminders/service.py` L149, L192 | FCM push integration for send & confirm |
| P0 | `tasks/weather_check.py` L128 | FCM push after weather trigger |
| P0 | `tasks/reminder_trigger.py` L110 | FCM push after timed trigger |
| P0 | `.env` | Real QWeather API key |
| P1 | `.env` | Real LLM API key |
| P1 | `reminders/service.py` L192 | Update achievement progress on confirm |
| P2 | `achievements/service.py` | Full unlock logic for different achievement types (currently only checks `target` count) |
