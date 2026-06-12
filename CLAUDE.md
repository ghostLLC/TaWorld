# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Flutter (from app/)
flutter pub get                                # install dependencies
flutter analyze                                # static analysis (must pass clean)
flutter run                                    # run on connected device/emulator
flutter build apk --release                    # build release APK (~93MB)
```

> **Note:** The `server/` directory contains a deprecated Python backend, kept for reference only. Do NOT run or modify it.

## Architecture

**Standalone Flutter App.** All data stored locally in SQLite via `sqflite` (DB version 4, 8 tables). No server, no network dependency for core features.

### App structure (`app/lib/`)

- `app/` — App entry, routing (GoRouter), theme (5 palettes × light/dark), design tokens
- `data/` — Models (user, partner, reminder_config, reminder_log, achievement, ai_wiki_fact), city_data (world cities), local SQLite (DatabaseHelper)
- `services/` — Business logic layer:
  - **AI Core:**
    - `ai_service.dart` — DeepSeek V4 Flash (chat) + V4 Pro (async tasks), API key management, DeepSeek context cache hit tracking
    - `ai_memory_service.dart` — Dynamic system prompt builder (`buildSystemPrompt()`), Wiki CRUD, summary management. Prompt structured for DeepSeek prefix caching: static sections first, volatile sections (time, RAG) last
    - `ai_memory_extractor.dart` — Post-conversation fact extraction using V4 Pro. Splits instructions into system message (cacheable) and data into user message
    - `ai_memory_dreamer.dart` — Background memory consolidation: Ebbinghaus decay, weak fact archival, LLM dedup/merge (V4 Pro), conversation summarization, old chunk cleanup. Runs daily via WorkManager
    - `ai_rag_service.dart` — Keyword-based RAG search (character bigram + Chinese stopwords + time decay weighting). No external embedding model needed
    - `ai_proactive_service.dart` — Proactive messaging with function calling (5 tools: create/delete reminders, get weather, list partners, get stats)
  - **Infrastructure:**
    - `weather_service.dart` — wttr.in free weather API (no key needed)
    - `notification_service.dart` — flutter_local_notifications zonedSchedule
    - `reminder_scheduler.dart` — Schedules all enabled reminder configs
    - `background_tasks.dart` — WorkManager periodic tasks (weather check + AI memory dreaming)
    - `theme_service.dart` — 5-palette theme switching with persistence
    - `local/` — SQLite CRUD services (user, partner, reminder, achievement)
- `presentation/` — UI layer:
  - `screens/` — 10 screens (ai_home, home, add_partner, partner_detail, reminder_config, reminder_history, achievements, onboarding, settings)
  - `widgets/` — Component library (TaCard, TaButton, TaTextField, TaAvatar, TaLoading, TaEmptyState, TaErrorState, TaAchievementBadge, TaStreakFlame, CityPickerSheet)

### AI Model Usage

| Model | Use Case | Cost (input/output per 1M tokens) |
|-------|----------|-------------------------------------|
| `deepseek-v4-flash` | Real-time chat, suggestions | ¥1 / ¥2 |
| `deepseek-v4-pro` | Memory extraction, Dreaming consolidation | ¥3 / ¥6 |

### AI Memory System (Wiki + RAG Hybrid)

Three-layer architecture:

1. **Wiki layer** (`ai_wiki_facts` table): Structured facts with category, importance, strength (decaying over time). Always injected into system prompt (top-20 by score). CRUD via `AiMemoryService`.

2. **RAG layer** (`conversation_chunks` table): Keyword-based search for historical conversations. Injected on-demand based on current user message relevance. No external embedding model — uses character bigram extraction + Chinese stopword filtering + time decay weighting.

3. **Summary layer** (`ai_conversation_summaries` table): Dreaming-generated summaries of old conversations. Injected as recent context (top-3).

**Dynamic System Prompt** (`buildSystemPrompt()`): Assembled per-request with sections ordered by stability for DeepSeek prefix caching:
```
[Base Instructions] → [User Identity] → [Partners] → [Reminders]  (semi-static)
→ [Wiki Facts] → [Summaries]  (session-level)
→ [Current Time (period only)] → [RAG Results]  (per-message)
```

Time is coarsened to period-of-day (not minute-precision) and placed near the end to maximize cache prefix length.

**Post-conversation pipeline** (fire-and-forget, non-blocking):
- `AiRagService.storeConversationChunks()` — store conversation for future recall
- `AiMemoryExtractor.extractFromConversation()` — extract facts via V4 Pro

**Background Dreaming** (daily via WorkManager):
- Ebbinghaus forgetting curve decay with category-specific half-lives
- Archive facts below strength threshold (0.08)
- LLM consolidation: dedup, contradiction resolution, merge (V4 Pro)
- Summarize old unsummarized conversations (V4 Pro)
- Clean conversation chunks older than 30 days

### DeepSeek Context Caching

Fully automatic server-side KV cache. No API parameters needed. Cache hit tokens cost 1/50 (Flash) or 1/120 (Pro) of regular input price. Tracked via `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` in API response `usage` field. Stats accumulated in SharedPreferences and displayed in Settings > AI Memory.

Key optimization: system prompt sections ordered by stability so the prefix stays byte-identical across consecutive requests within the same time period (~3-6 hours).

### Navigation

3-tab bottom NavigationBar with IndexedStack:

| Tab | Screen | Description |
|-----|--------|-------------|
| 1 | AI Assistant (`AiHomeScreen`) | AI chat + proactive messages + quick chips + function calling |
| 2 | Partners (`_PartnersTab` in `HomeScreen`) | Expandable partner cards with city/time/weather |
| 3 | Profile (`_ProfileTab` in `HomeScreen`) | Profile + stats + menu |

### Routes (defined in `lib/app/router.dart`)

```dart
Routes.home = '/'
Routes.onboarding = '/onboarding'
Routes.addPartner = '/partners/add'
Routes.partnerDetail = '/partners/:id'
Routes.reminderConfig = '/reminders/config/:partnerId'
Routes.reminderHistory = '/reminders/:id/logs'
Routes.achievements = '/achievements'
Routes.settings = '/settings'
```

## Key Conventions

### Design tokens

All visual values come from `lib/app/design_tokens.dart`. Never hardcode colors, spacing, or radius. Use `TaSpacing.md`, `TaRadius.borderMd`, `theme.colorScheme.primary`, etc.

### Theme system

5 color palettes (warm coral, ocean blue, forest green, lavender, sunset orange), each with light and dark variants. Theme mode (system/light/dark) and palette index persisted via `ThemeService` (SharedPreferences).

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

### Database

SQLite via `sqflite`. Current version: 4. Tables: user, partners, reminder_configs, reminder_logs, achievements, ai_wiki_facts, ai_conversation_summaries, conversation_chunks, chat_history. Migration handled in `_onUpgrade`.

### Partner cards

Each partner card shows: avatar, nickname, city, relationship type, days together, local time (estimated from longitude), real-time weather (emoji + description + temp), and reminder count badge.

### City picker

`showCityPicker()` bottom sheet. Returns `CitySelection` with city, province, country. Data from `city_data.dart` (24 countries, 300+ cities, default China).

### Location permission

3-stage check: GPS service → permission request → get position. Uses `geolocator` + `permission_handler`.

### Weather

wttr.in free API, no key needed. `WeatherResult` has text, temp, windDir, humidity. `checkConditions()` for alert triggers.

### AI

DeepSeek V4 API. Two models: `deepseek-v4-flash` (real-time chat, low cost) and `deepseek-v4-pro` (async tasks, stronger reasoning). User-configured key stored in SharedPreferences. `AiService.chat()` / `streamChat()` / `chatWithTools()` for conversation. `AiService.callProModel()` for async tasks with optional `systemPrompt` parameter for cache optimization. Chat history persisted in `chat_history` SQLite table.

### Proactive messaging

`AiProactiveService` builds rich context (partners, weather, reminders) and uses function calling (5 tools) for AI-driven actions like creating reminders or querying weather. Results delivered as local notifications.

### Notifications

`flutter_local_notifications` with `zonedSchedule()` for precise timing. `ReminderScheduler.scheduleAll()` reschedules all enabled configs.

### Background tasks

`WorkManager` for periodic tasks:
- Weather check (periodic)
- AI memory Dreaming (daily, calls `AiMemoryDreamer.dream()`)

### Achievement badges

`TaAchievementBadge` widget. No points system — just "已解锁" / progress display.

## Gotchas

- `flutter analyze` must pass clean before any commit
- All UI uses design tokens from `design_tokens.dart` — never hardcode visual values
- `city_data.dart` replaced `china_cities.dart` — import the correct file
- The `server/` directory is deprecated — don't modify or run it
- Partner local time is estimated from longitude (`lng / 15` hours from UTC) — approximate but sufficient for display
- `TaAchievementBadge` no longer has a `points` parameter
- `callProModel()` supports optional `systemPrompt` — always use it when the instruction text is static across multiple calls (for DeepSeek cache optimization)
- Time in system prompt is coarsened to period-of-day only (no minutes) and placed near the end — this is intentional for DeepSeek prefix caching
- Post-conversation memory extraction and RAG storage are fire-and-forget (`.catchError((_) {})`) — they must never block the chat UI
