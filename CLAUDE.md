# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Flutter (from app/)
flutter pub get                                # install dependencies
flutter analyze                                # static analysis (must pass clean)
flutter run                                    # run on connected device/emulator
flutter build apk --release                    # build release APK (~55MB)
```

> **Note:** The `server/` directory contains a deprecated Python backend, kept for reference only. Do NOT run or modify it.

## Architecture

**Standalone Flutter App.** All data stored locally in SQLite via `sqflite`. No server, no network dependency for core features.

### App structure (`app/lib/`)

- `app/` — App entry, routing (GoRouter), theme (Material 3), design tokens
- `data/` — Models (user, partner, reminder_config, reminder_log, achievement), city_data (world cities), local SQLite (DatabaseHelper)
- `services/` — Business logic layer:
  - `ai_service.dart` — DeepSeek AI chat + API key management (SQLite chat_history table)
  - `weather_service.dart` — wttr.in free weather API (no key needed)
  - `notification_service.dart` — flutter_local_notifications zonedSchedule
  - `reminder_scheduler.dart` — Schedules all enabled reminder configs as local notifications
  - `background_tasks.dart` — WorkManager periodic background tasks
  - `local/` — SQLite CRUD services (user, partner, reminder, achievement)
- `presentation/` — UI layer:
  - `screens/` — 11 screens (ai_home, home, add_partner, partner_detail, reminder_config, reminder_history, achievements, ai_chat, api_key_setup, onboarding, settings)
  - `widgets/` — Component library (TaCard, TaButton, TaTextField, TaAvatar, TaLoading, TaEmptyState, TaErrorState, TaAchievementBadge, CityPickerSheet)

### Navigation

3-tab bottom NavigationBar with IndexedStack:

| Tab | Screen | Description |
|-----|--------|-------------|
| 1 | AI 助手 (`AiHomeScreen`) | AI chat + proactive messages + quick chips |
| 2 | 关心的人 (`_PartnersTab` in `HomeScreen`) | Expandable partner cards with city/time/weather |
| 3 | 我的 (`_ProfileTab` in `HomeScreen`) | Profile + stats + menu |

### Routes (defined in `lib/app/router.dart`)

```dart
Routes.home = '/'
Routes.onboarding = '/onboarding'
Routes.addPartner = '/partners/add'
Routes.partnerDetail = '/partners/:id'
Routes.reminderConfig = '/reminders/config/:partnerId'
Routes.reminderHistory = '/reminders/:id/logs'
Routes.achievements = '/achievements'
Routes.aiChat = '/ai/chat'
Routes.apiKeys = '/settings/api-keys'
Routes.settings = '/settings'
```

## Key Conventions

### Design tokens

All visual values come from `lib/app/design_tokens.dart`. Never hardcode colors, spacing, or radius. Use `TaSpacing.md`, `TaRadius.borderMd`, `theme.colorScheme.primary`, etc.

### State management

Plain `StatefulWidget` + `setState`. No Riverpod/Bloc. Each screen manages its own loading/error/data states.

### Animations

Use the `flutter_animate` package with the standard durations:

- `TaAnimation.fast` — 200ms
- `TaAnimation.normal` — 300ms
- `TaAnimation.slow` — 500ms
- `TaAnimation.curve` — easeInOutCubic

### Data flow

```
Screens → Services (local/ or weather/ai) → SQLite/HTTP
```

No repository pattern. Services are static methods on abstract classes.

### Partner cards

Each partner card shows: avatar, nickname, city, relationship type, days together, local time (estimated from longitude), real-time weather (emoji + description + temp), and reminder count badge.

### City picker

`showCityPicker()` bottom sheet. Returns `CitySelection` with city, province, country. Data from `city_data.dart` (24 countries, 300+ cities, default China).

### Location permission

3-stage check: GPS service → permission request → get position. Uses `geolocator` + `permission_handler`.

### Weather

wttr.in free API, no key needed. `WeatherResult` has text, temp, windDir, humidity. `checkConditions()` for alert triggers.

### AI

DeepSeek API, user-configured key stored in SQLite. `AiService.chat()` for conversation, `AiService.generateSuggestion()` for care suggestions. Chat history persisted in `chat_history` SQLite table.

### Notifications

`flutter_local_notifications` with `zonedSchedule()` for precise timing. `ReminderScheduler.scheduleAll()` reschedules all enabled configs.

### Background tasks

`WorkManager` for periodic tasks. Triggers weather checks and reminder maintenance.

### Achievement badges

`TaAchievementBadge` widget. No points system — just "已解锁" / progress display.

## Gotchas

- `flutter analyze` must pass clean before any commit
- All UI uses design tokens from `design_tokens.dart` — never hardcode visual values
- `city_data.dart` replaced `china_cities.dart` — import the correct file
- The `server/` directory is deprecated — don't modify or run it
- API Key management page (`api_key_setup_screen.dart`) should NOT mention weather services
- Partner local time is estimated from longitude (`lng / 15` hours from UTC) — approximate but sufficient for display
- `TaAchievementBadge` no longer has a `points` parameter
