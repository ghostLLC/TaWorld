# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# ---- Backend (from server/) ----
venv\Scripts\activate                          # activate venv
uvicorn app.main:app --reload --port 8000      # dev server
pytest                                         # all tests (33)
pytest tests/test_auth.py -k test_login        # single test

# Database (from server/ — Chinese Windows MUST set PYTHONUTF8=1)
$env:PYTHONUTF8=1; alembic upgrade head        # apply migrations
$env:PYTHONUTF8=1; alembic revision --autogenerate -m "desc"  # generate new migration
$env:PYTHONUTF8=1; alembic downgrade -1        # rollback

# Infrastructure (from repo root)
docker-compose up -d postgres redis            # start DB + cache
docker-compose ps                              # check status

# ---- Flutter (when frontend is created) ----
flutter doctor                                 # verify environment
flutter create app                             # create Flutter project in app/
cd app; flutter run -d chrome                  # run in browser
```

## Architecture

**Modular Monolith.** The single FastAPI app (`server/app/main.py`) registers 7 business modules under `/api/v1`. Each module follows a strict 4-layer dependency order:

```
models.py  →  schemas.py  →  service.py  →  router.py
  (DB)         (validation)    (logic)        (HTTP)
```

**Core layer** (`server/app/core/`): `config.py` (pydantic-settings), `database.py` (async engine + `UUIDMixin`/`TimestampMixin`), `security.py` (JWT + bcrypt), `dependencies.py` (auth deps + Redis pool), `push_service.py` (FCM with graceful degradation), `storage.py` (MinIO avatar upload, degrades gracefully when MinIO unreachable).

**Common layer** (`server/app/common/`): `response.py` (unified `{code, message, data}`), `exceptions.py` (hierarchy: `1xxx` Auth, `2xxx` User, `3xxx` Relationship, `4xxx` Reminder, `5xxx` System), `pagination.py`, `rate_limit.py` (auth endpoints: 10req/60s, localhost exempt).

**Tasks** (`server/app/tasks/`): APScheduler — weather check (hourly), timed reminder (per minute). Started in FastAPI `lifespan`, use `async_session_factory()` directly (must commit/rollback manually).

**Infrastructure**: PostgreSQL 16 + Redis 7 via Docker Compose (both healthy). MinIO service defined in `docker-compose.yml` for avatar storage (image pull may fail on mainland China networks — code degrades gracefully). Database has 9 tables at migration `0001`.

**Flutter**: SDK 3.41.9 installed at `C:\flutter\`. Android toolchain ready (SDK 36). PATH includes `C:\flutter\bin`.

## Key Conventions

### Response format
All endpoints return `{code: 0, message: "success", data: {...}}`. Use helpers: `success_response()`, `paginated_response()`. Never return raw dicts.

### Error handling
Use custom exceptions from `app/common/exceptions.py`. Never `raise HTTPException` directly. The global handler converts `AppException` to unified response format.

### Authentication
Protected routes use `current_user: Annotated[User, Depends(get_current_active_user)]`. The `get_current_user` dep validates JWT + fetches User. `get_current_active_user` wraps it (extension point for status checks).

### Database session
`get_db()` auto-commits on success, auto-rollbacks on exception. Services called from routes don't need explicit `commit()`. Tasks using `async_session_factory()` directly MUST commit/rollback manually.

### Models
Use `Base, UUIDMixin, TimestampMixin` from `database.py`. Types use cross-DB SQLAlchemy 2.0: `sa.Uuid` (not `postgresql.UUID`), `sa.JSON` (not `postgresql.JSONB`). This allows SQLite for tests and PostgreSQL for production.

### Push notifications
`PushService.send()` from `app/core/push_service.py`. When `FCM_SERVER_KEY` is not configured, it logs the message and returns (no error). This means all TODO locations (reminders, weather_check, reminder_trigger) are wired and working — they just need a real key to actually deliver.

## API Overview (35 routes)

| Module | Key endpoints |
|--------|--------------|
| Auth | `POST register/login/refresh` |
| Users | `GET/PUT /me`, `PUT /me/location`, `POST /me/devices`, `GET /me/stats`, `POST/DELETE /me/avatar` |
| Relationships | `POST invite/join`, `GET/PUT/DELETE /{id}`, `GET ""` (list with partner info) |
| Reminders | CRUD configs, `POST send/confirm`, `GET logs/stats` |
| Weather | `GET /current` |
| Achievements | `GET /achievements`, `GET /users/me/achievements` |
| AI | `POST /suggest`, `POST /chat` |
| System | `GET /`, `GET /health`, `GET /api/v1/config` |

## Gotchas

- **`PYTHONUTF8=1` required** for Alembic on Chinese Windows (alembic reads config with `encoding="locale"` which is GBK, failing on ASCII-incompatible bytes).
- **Tests use SQLite** (`sqlite+aiosqlite:///./test.db`) with an `autouse` fixture that creates/drops tables per test and seeds achievement data. The `auth_client` fixture generates unique phone numbers per call.
- **Weather module has no DB models** — all data is Redis-cached (TTL 30 min). It only has `schemas.py`, `service.py`, `router.py`.
- **Reminder direction**: the system notifies `config.created_by` (the person being prompted to care) about the partner (the other user in the relationship). Both `weather_check.py` and `reminder_trigger.py` now respect `created_by` — not hardcoded `user_a`.
- **AI and Push degrade gracefully**: if API keys are missing, AI returns preset fallback templates and PushService just logs. No errors thrown.
- **Achievement unlock logic** supports 4 types: `count` (simple increment), `streak_days` (consecutive days with reminders), `mutual_reminder_count` (min of A→B and B→A), `relationship_days` (days since relationship created). Pass `context={"partner_id": ...}` for mutual/relationship types.
- **Test database** at `server/test.db` is gitignored (`*.db` in `.gitignore`).
- **Avatar upload** uses `StorageService` from `app/core/storage.py`. Accepts JPEG/PNG/WebP (max 2MB). When MinIO is unreachable, raises `SystemException(503)`. Old avatar is auto-deleted on new upload.
