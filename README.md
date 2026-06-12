# TaWorld

<p align="center">
  <strong>A care-first emotional connection APP</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.41.9-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

> A fully offline, standalone APP centered around caring for others. You add the people you care about, configure reminders, and the APP reminds you at the right moments to reach out and care for them — it never contacts them directly. All data stays on your phone. No server, no cloud.
>
> The AI assistant (DeepSeek V4) proactively sends you weather alerts, greetings, and care suggestions, while remembering what you've talked about across sessions through a Wiki + RAG hybrid memory architecture.

## Core Features

| Feature | Description | Status |
|---------|-------------|--------|
| **AI Care Assistant** | DeepSeek V4 Flash (real-time chat) + V4 Pro (async tasks). Dynamic system prompt with full context injection | Done |
| **AI Memory System** | Wiki + RAG hybrid architecture: structured facts (Wiki), keyword-based recall (RAG), Ebbinghaus decay, Dreaming consolidation | Done |
| **Proactive Messaging** | AI proactively sends weather alerts, reminders, and care suggestions via function calling | Done |
| **Partner Management** | Add/edit/delete people you care about, GPS + city picker (24 countries, 300+ cities) | Done |
| **Smart Reminders** | Sleep/meal/weather/custom reminders, local precise scheduling via WorkManager | Done |
| **Real-time Weather** | wttr.in free weather (no API key), partner city cards with local time and weather | Done |
| **Achievement System** | 7 badges, 4 unlock logics (count/streak/mutual/relationship_days) | Done |
| **Theme System** | 5 color palettes (warm coral, ocean blue, forest green, lavender, sunset orange), light/dark mode | Done |
| **City Picker** | Bottom sheet with search + browse, 24 countries, 300+ cities | Done |
| **GPS Location** | geolocator + permission_handler, 3-stage permission check | Done |

### Design Principles

```
People are the bridge    APP reminds A to care for B — never contacts B directly
Privacy first            No exposed locations; position only used for weather queries
Warm and simple          Material 3, rounded design, 8px baseline grid
Standalone first         No server dependency; all data in local SQLite
```

---

## Technical Architecture

Pure client-side standalone architecture. All data stored in local SQLite. AI and weather services connect directly from the device to external APIs.

### Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Framework | Flutter 3.41.9 + Dart | Cross-platform, Material 3 warm style |
| Routing | GoRouter | Declarative routing + auth redirect |
| Database | SQLite (sqflite) | All data local, DB version 4 |
| AI (chat) | DeepSeek V4 Flash | Low-latency real-time conversation |
| AI (async) | DeepSeek V4 Pro | Memory extraction, Dreaming consolidation |
| AI Memory | Wiki + RAG hybrid | Structured facts + keyword recall, Ebbinghaus decay |
| Prompt Cache | DeepSeek Context Caching | Automatic KV cache, 50-120x cost reduction on cache hits |
| Weather | wttr.in | Free, no API key needed |
| Notifications | flutter_local_notifications | zonedSchedule precise dispatch |
| Background | WorkManager | Periodic task scheduling |
| Location | geolocator + permission_handler | GPS + permission management |
| Animation | flutter_animate | Fade-in, elastic effects |
| HTTP | Dio | Network requests (weather/AI) |
| UI | Material 3 + custom design system | 5 color palettes, 8px baseline grid |

### AI Memory Architecture

```
                    Post-conversation (async, V4 Pro)
                    ┌──────────────────────────────────┐
                    │     AiMemoryExtractor            │
                    │  Extract facts from conversation  │
                    └──────────┬───────────────────────┘
                               │ write
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                     Dynamic System Prompt                     │
│                                                              │
│  [Base Instructions] [User Identity] [Partners] [Reminders] │  ← Semi-static
│  [Wiki Facts (top-20)] [Conversation Summaries]              │  ← Session-level
│  [Current Time (coarsened)] [RAG Results]                    │  ← Per-message
│                                                              │
│  Optimized for DeepSeek Context Caching (prefix-friendly)    │
└──────────────────────────────────────────────────────────────┘
                               ▲
                               │ read
                    ┌──────────┴───────────────────────┐
                    │     AiMemoryService               │
                    │  buildSystemPrompt() per request   │
                    └──────────────────────────────────┘

Background (daily, V4 Pro)
┌──────────────────────────────────────────────────────────────┐
│                    AiMemoryDreamer                            │
│  Ebbinghaus decay → Archive weak → LLM consolidation        │
│  → Summarize old conversations → Clean old chunks            │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                     AiRagService                              │
│  Keyword-based search (bigram + stopwords + time decay)      │
│  No external embedding model needed                          │
└──────────────────────────────────────────────────────────────┘
```

### App Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Flutter APP (Android)                   │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  presentation│  │   services   │  │     data      │  │
│  │   (UI)       │──│  (business)  │──│   (storage)   │  │
│  │  screens/    │  │  ai_service  │  │  models/      │  │
│  │  widgets/    │  │  ai_memory_* │  │  SQLite DB    │  │
│  └──────────────┘  │  ai_rag_*    │  │  city_data    │  │
│                     │  weather_svc │  └───────────────┘  │
│                     │  notif_svc   │                     │
│                     │  proactive   │                     │
│                     └──────┬───────┘                     │
└────────────────────────────┼─────────────────────────────┘
                             │ HTTPS (direct)
                    ┌────────┴────────┐
                    ▼                 ▼
              ┌──────────┐     ┌───────────┐
              │ DeepSeek  │     │  wttr.in  │
              │  V4 API   │     │  Weather  │
              └──────────┘     └───────────┘
```

---

## Project Structure

```
TaWorld/
├── app/                               # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart                  # Entry point
│   │   ├── app/                       # App-level config
│   │   │   ├── app.dart               # MaterialApp root
│   │   │   ├── router.dart            # GoRouter routes
│   │   │   ├── theme.dart             # 5 color palettes (light+dark)
│   │   │   └── design_tokens.dart     # Design tokens
│   │   ├── data/                      # Data layer
│   │   │   ├── models/                # Data models
│   │   │   │   ├── user.dart
│   │   │   │   ├── partner.dart
│   │   │   │   ├── reminder_config.dart
│   │   │   │   ├── reminder_log.dart
│   │   │   │   ├── achievement.dart
│   │   │   │   └── ai_wiki_fact.dart  # Wiki memory fact model
│   │   │   ├── city_data.dart         # World cities (24 countries, 300+ cities)
│   │   │   └── local/database_helper.dart  # SQLite (DB v4, 8 tables)
│   │   ├── services/                  # Business logic
│   │   │   ├── ai_service.dart        # DeepSeek V4 chat + Pro model + cache tracking
│   │   │   ├── ai_memory_service.dart # Dynamic system prompt builder + Wiki CRUD
│   │   │   ├── ai_memory_extractor.dart # Post-conversation fact extraction (V4 Pro)
│   │   │   ├── ai_memory_dreamer.dart # Background memory consolidation (V4 Pro)
│   │   │   ├── ai_rag_service.dart    # Keyword-based RAG search
│   │   │   ├── ai_proactive_service.dart # Proactive messaging + function calling
│   │   │   ├── weather_service.dart   # wttr.in weather
│   │   │   ├── notification_service.dart # Local notifications
│   │   │   ├── reminder_scheduler.dart # Reminder scheduling
│   │   │   ├── background_tasks.dart  # WorkManager tasks (weather + dreaming)
│   │   │   ├── care_suggestion_service.dart
│   │   │   ├── theme_service.dart     # 5-palette theme switching
│   │   │   └── local/                 # Local CRUD services
│   │   │       ├── local_user_service.dart
│   │   │       ├── partner_service.dart
│   │   │       ├── local_reminder_service.dart
│   │   │       └── local_achievement_service.dart
│   │   └── presentation/              # UI layer
│   │       ├── screens/
│   │       │   ├── ai_home/           # AI chat (Tab 1)
│   │       │   ├── home/              # Partners + Profile (Tab 2 & 3)
│   │       │   ├── add_partner/
│   │       │   ├── partner_detail/
│   │       │   ├── reminder_config/
│   │       │   ├── reminder_history/
│   │       │   ├── achievements/
│   │       │   ├── onboarding/
│   │       │   └── settings/          # Settings + AI memory management
│   │       └── widgets/               # Component library
│   │           ├── widgets.dart       # Unified exports
│   │           ├── city_picker_sheet.dart
│   │           ├── ta_card.dart / ta_button.dart / ta_text_field.dart
│   │           ├── ta_avatar.dart / ta_loading.dart
│   │           ├── ta_achievement_badge.dart
│   │           └── ta_streak_flame.dart
│   └── pubspec.yaml
│
├── server/                            # [Deprecated] Python backend (historical only)
│
├── docs/                              # Project documentation
│   ├── design_system.md               # Design system spec (current)
│   ├── frontend_guide.md              # Frontend dev guide (current)
│   ├── ai_memory_implementation_plan.md # AI memory architecture plan
│   ├── prompt_caching_optimization_plan.md # DeepSeek cache optimization
│   ├── ai_proactive_research.md       # Proactive messaging research
│   ├── asset_upgrade_plan.md          # Asset upgrade plan
│   ├── standalone_refactor_plan.md    # Standalone migration record
│   ├── architecture.md                # Old architecture (historical)
│   ├── developer_guide.md             # Old backend guide (historical)
│   └── walkthrough.md                 # Old backend report (historical)
│
├── CLAUDE.md                          # AI assistant context
├── README.md
└── .gitignore
```

> The `server/` directory contains deprecated Python backend code, kept only for historical reference.

---

## Navigation

3-tab bottom NavigationBar:

| Tab | Page | Description |
|-----|------|-------------|
| 1 | AI Assistant (AiHomeScreen) | AI chat + proactive messages + quick chips |
| 2 | Partners (_PartnersTab) | Expandable card list with city/time/weather |
| 3 | Profile (_ProfileTab) | Avatar/stats/menu |

### Routes

| Path | Page |
|------|------|
| `/` | Home (3-tab bottom nav) |
| `/onboarding` | Onboarding |
| `/partners/add` | Add partner |
| `/partners/:id` | Partner detail/edit |
| `/reminders/config/:partnerId` | Reminder config |
| `/reminders/:id/logs` | Reminder history |
| `/achievements` | Achievements |
| `/settings` | Settings |

---

## Quick Start

### Prerequisites

- Flutter 3.41.9+
- Android device or emulator

### Run

```bash
cd app
flutter pub get
flutter run
```

### Build release APK

```bash
flutter build apk --release
```

No server to start, no database to configure, no Docker to orchestrate.

---

## Privacy

TaWorld is a fully offline APP:

- All data stored in device-local SQLite — no server, no cloud sync
- AI API Key (DeepSeek) configured by the user, direct connection from device
- Weather queries go directly to wttr.in, no intermediary
- No data collection, no telemetry
- Location used only for weather display, never shared

---

## Documentation Index

### Current

| Document | Description |
|----------|-------------|
| [Design System](docs/design_system.md) | Design tokens, colors, typography, component specs |
| [Frontend Guide](docs/frontend_guide.md) | Flutter development conventions, component patterns |
| [AI Memory Plan](docs/ai_memory_implementation_plan.md) | Wiki + RAG hybrid memory architecture |
| [Prompt Caching Plan](docs/prompt_caching_optimization_plan.md) | DeepSeek context caching optimization |
| [Proactive Messaging Research](docs/ai_proactive_research.md) | AI proactive messaging design research |
| [Standalone Refactor](docs/standalone_refactor_plan.md) | Server-to-standalone migration record |

### Historical (deprecated Python backend)

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | Old FastAPI + PostgreSQL + Redis design |
| [Developer Guide](docs/developer_guide.md) | Old backend module conventions |
| [Walkthrough](docs/walkthrough.md) | Old backend acceptance report |

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'feat: add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

<p align="center">
  Made with care by TaWorld Team
</p>
