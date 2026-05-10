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
docker-compose up -d postgres redis minio      # start all infrastructure
docker-compose ps                              # check status

# ---- Flutter (from app/) ----
flutter pub get                                # install dependencies
flutter analyze                                # static analysis
flutter run -d chrome                          # run in browser
flutter run                                    # run on connected device/emulator
flutter build apk --release                    # build release APK
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

**Infrastructure**: PostgreSQL 16 + Redis 7 + MinIO via Docker Compose (all healthy). If Docker Hub is unreachable, pull images via `docker pull docker.m.daocloud.io/<image>:<tag>` then tag to the expected name. Database has 9 tables at migration `0001`.

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

## Flutter Frontend (app/)

**Design System.** The app uses a pre-built design system. All colors, spacing, radius, and shadows are defined in `lib/app/design_tokens.dart`. Never hardcode visual values — use `TaSpacing`, `TaRadius`, `TaLightColors`/`TaDarkColors`, etc.

**Theme.** `lib/app/theme.dart` provides full Material 3 `ThemeData` for both light and dark modes. Use `Theme.of(context).colorScheme.primary` to get colors.

**Component Library** (`lib/presentation/widgets/`): `TaCard`, `TaButton`, `TaTextField`, `TaAvatar`, `TaNotificationCard`, `TaAchievementBadge`, `TaLoading`, `TaEmptyState`, `TaErrorState`. Import via `widgets.dart` barrel file.

**Reference Pages:** `login_screen.dart` and `home_screen.dart` demonstrate the standard patterns for building pages (component usage, API calls, state management, animations).

**Routing.** `lib/app/router.dart` uses GoRouter. All routes are defined with `_Placeholder` widgets. Replace them with real implementations. Auth redirect is automatic (unauthenticated users → login).

**API Layer.** `dio_client.dart` provides a pre-configured Dio with auto token injection and 401 refresh. `api_endpoints.dart` has all backend route paths. `api_response.dart` models the `{code, message, data}` format.

**Animations.** Use `flutter_animate` package with `TaAnimation.normal` duration and `TaAnimation.curve`. See `login_screen.dart` for entrance animation examples.

**Full guide:** See `docs/frontend_guide.md` for component usage examples, styling rules, and page implementation checklist.

