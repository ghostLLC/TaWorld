# TaWorld 单机版改造方案

> **版本**: v1.0  
> **日期**: 2026-06-10  
> **目标**: 将 TaWorld 从服务器-客户端架构改造为纯单机 Flutter 应用，无需任何后端服务器即可运行

---

## 一、改造概述

### 1.1 目标架构

当前架构：Flutter App → FastAPI Server → PostgreSQL / Redis / MinIO / FCM

目标架构：Flutter App → SQLite（本地） + DeepSeek API（直连） + 和风天气 API（直连） + 本地通知

### 1.2 核心原则

- **零服务器依赖**：App 不连接任何自建后端，所有数据存本地
- **API Key 用户自持**：DeepSeek / 和风天气的 API Key 由用户在设置页自行填入，不硬编码
- **功能对等**：单机版保留服务器版的核心业务逻辑（关系管理、提醒、成就、AI），仅砍掉多人联网特性
- **渐进式改造**：尽量复用现有 UI 层代码，重写数据层和服务层

### 1.3 保留与砍掉的功能

| 功能 | 决定 | 原因 |
|------|------|------|
| 注册/登录 | 改为本地昵称设置 | 单机无需账号体系 |
| 关系管理（邀请码） | 改为本地添加"关心的人" | 单机无网络配对，改为手动输入对方信息 |
| 提醒配置与触发 | 保留，改为本地通知 | 核心功能，用 `flutter_local_notifications` 替代 FCM |
| 提醒历史 | 保留 | 纯本地数据 |
| 成就系统 | 保留 | 本地计算，逻辑用 Dart 重写 |
| AI 对话 | 保留，直连 DeepSeek | OpenAI 兼容 API，Dio 直接调用 |
| AI 关怀建议 | 保留，直连 DeepSeek | 同上 |
| 天气查询 | 保留，直连和风天气 | REST API，客户端直接调 |
| 天气自动检查 | 改为本地定时任务 | 用 `workmanager` 替代 APScheduler |
| 头像上传（MinIO） | 改为本地相册选择 | 存本地文件系统 |
| FCM 推送 | 移除 | 替换为本地通知 |
| Token/JWT 认证 | 移除 | 无服务端，无需认证 |
| 统计数据 | 保留 | 从本地 SQLite 计算 |

---

## 二、新增依赖

### 2.1 需要添加的 pub 依赖

```yaml
dependencies:
  # 本地数据库
  sqflite: ^2.4.2          # SQLite（已在依赖中）
  path: ^1.9.0             # 数据库文件路径
  uuid: ^4.5.1             # UUID 生成（替代服务端 uuid4）

  # 本地通知与定时任务
  flutter_local_notifications: ^18.0.0  # 替代 FCM
  workmanager: ^0.5.2                   # 后台定时任务（天气检查、提醒触发）
  timezone: ^0.9.4                      # 时区处理

  # 权限
  permission_handler: ^11.3.1  # 通知权限、定位权限

  # 图片选择（替代 MinIO 上传）
  image_picker: ^1.1.2     # 从相册选择头像
```

### 2.2 可移除的依赖

```yaml
# 以下依赖在单机版中不再需要：
flutter_riverpod        # 未实际使用，可清理
riverpod_annotation     # 同上
riverpod_generator      # 同上（dev）
cached_network_image    # 头像改本地文件，无需网络缓存
firebase_messaging      # FCM 已注释，彻底移除
```

### 2.3 保留的依赖

```yaml
go_router              # 路由，保留
dio                    # HTTP，用于调 DeepSeek 和和风天气 API
shared_preferences     # 轻量 KV 存储（API Key、设置项）
hive_flutter / hive    # 可作为配置缓存保留
intl                   # 日期格式化
google_fonts           # 保留，但需内嵌字体文件（离线兜底）
flutter_animate        # 动画
shimmer                # 骨架屏
flutter_svg            # SVG 渲染
geolocator             # 启用，用于获取用户位置（天气查询需要）
```

---

## 三、本地数据库设计

### 3.1 数据库文件

使用 `sqflite`，数据库文件名 `taworld.db`，存放在 App 私有目录（`getDatabasesPath()`）。

### 3.2 表结构

#### 表1: `users`（本地用户，仅一条记录）

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,                    -- UUID
  nickname TEXT NOT NULL DEFAULT '',      -- 昵称
  avatar_path TEXT,                       -- 本地头像文件路径（非 URL）
  phone TEXT,                             -- 手机号（可选，仅展示用）
  created_at TEXT NOT NULL,               -- ISO8601
  updated_at TEXT NOT NULL                -- ISO8601
);
```

单机版只有一个"本机用户"，首次启动时引导设置昵称即可。

#### 表2: `partners`（关心的人 —— 替代原 relationships 中的 user_b）

```sql
CREATE TABLE partners (
  id TEXT PRIMARY KEY,                    -- UUID
  nickname TEXT NOT NULL,                 -- 对方昵称
  avatar_path TEXT,                       -- 本地头像
  type TEXT NOT NULL DEFAULT 'couple',    -- couple / family / friend
  note TEXT,                              -- 备注
  latitude REAL,                          -- 对方位置（天气查询用）
  longitude REAL,
  city TEXT,
  district TEXT,
  status TEXT NOT NULL DEFAULT 'active',  -- active / dissolved
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

单机版中，"关系"简化为本地添加的联系人。不需要邀请码配对，用户直接输入对方的昵称和基本信息。

#### 表3: `reminder_configs`（提醒配置）

```sql
CREATE TABLE reminder_configs (
  id TEXT PRIMARY KEY,
  partner_id TEXT NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  category TEXT NOT NULL,                 -- weather / sleep / meal / custom
  enabled INTEGER NOT NULL DEFAULT 1,     -- SQLite 用 0/1 代替 boolean
  config TEXT NOT NULL DEFAULT '{}',      -- JSON 字符串
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

`config` 字段存储 JSON 字符串，内部结构与服务器版一致。

#### 表4: `reminder_logs`（提醒日志）

```sql
CREATE TABLE reminder_logs (
  id TEXT PRIMARY KEY,
  config_id TEXT NOT NULL REFERENCES reminder_configs(id) ON DELETE CASCADE,
  partner_id TEXT NOT NULL REFERENCES partners(id),
  message TEXT,
  status TEXT NOT NULL DEFAULT 'triggered',  -- triggered / sent / confirmed
  triggered_at TEXT NOT NULL,
  sent_at TEXT,
  confirmed_at TEXT
);
```

单机版中 sender/receiver 简化为：本机用户是 sender，partner 是 receiver。

#### 表5: `achievements`（成就定义）

```sql
CREATE TABLE achievements (
  id TEXT PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  icon TEXT NOT NULL DEFAULT 'trophy',
  category TEXT NOT NULL DEFAULT 'general',
  unlock_condition TEXT NOT NULL DEFAULT '{}',  -- JSON 字符串
  points INTEGER NOT NULL DEFAULT 0
);
```

App 首次启动时插入 7 个预设成就（与服务器版 `seed_achievements()` 一致）。

#### 表6: `user_achievements`（成就进度）

```sql
CREATE TABLE user_achievements (
  id TEXT PRIMARY KEY,
  achievement_id TEXT NOT NULL REFERENCES achievements(id),
  progress INTEGER NOT NULL DEFAULT 0,
  unlocked INTEGER NOT NULL DEFAULT 0,       -- 0/1
  unlocked_at TEXT
);
```

#### 表7: `chat_history`（AI 对话历史 —— 新增）

```sql
CREATE TABLE chat_history (
  id TEXT PRIMARY KEY,
  role TEXT NOT NULL,       -- user / assistant
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
);
```

服务器版对话历史不持久化，单机版新增此表以支持多轮上下文对话。

### 3.3 数据库管理

新建 `app/lib/data/local/database_helper.dart`，单例模式管理数据库生命周期：

```dart
class DatabaseHelper {
  static Database? _database;

  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'taworld.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(/* 上述 7 张表的 CREATE TABLE */);
        await _seedAchievements(db);  // 插入预设成就
      },
    );
  }
}
```

---

## 四、服务层重写

### 4.1 新增本地服务类

替换原有的 API 调用，新建以下服务（放在 `app/lib/services/local/` 目录）：

| 服务类 | 替代原 | 职责 |
|--------|--------|------|
| `LocalUserService` | `AuthService` + 后端 `/users/*` | 本地用户 CRUD、昵称/头像管理 |
| `PartnerService` | 后端 `/relationships/*` | 关心的人 CRUD |
| `LocalReminderService` | 后端 `/reminders/*` | 提醒配置 CRUD、日志、统计 |
| `LocalAchievementService` | 后端 `/achievements/*` | 成就进度计算（4种逻辑用 Dart 重写） |
| `AiService` | 后端 `/ai/*` | 直连 DeepSeek API |
| `WeatherService` | 后端 `/weather/*` | 直连和风天气 API |
| `NotificationService` | 后端 FCM + APScheduler | 本地通知调度、定时任务 |

### 4.2 LocalUserService 设计

```dart
abstract final class LocalUserService {
  /// 获取本机用户（唯一记录）
  static Future<Map<String, dynamic>?> getUser();

  /// 首次设置昵称（创建本地用户）
  static Future<Map<String, dynamic>> createUser(String nickname);

  /// 更新昵称
  static Future<void> updateNickname(String nickname);

  /// 设置头像（从相册选择，复制到 App 私有目录）
  static Future<void> setAvatar(String filePath);

  /// 获取统计数据（关系数、提醒数、连续天数）
  static Future<Map<String, dynamic>> getStats();
}
```

### 4.3 PartnerService 设计

```dart
abstract final class PartnerService {
  /// 获取所有关心的人
  static Future<List<Map<String, dynamic>>> getAll();

  /// 添加关心的人
  static Future<Map<String, dynamic>> add({
    required String nickname,
    required String type,   // couple / family / friend
    String? note,
  });

  /// 获取详情
  static Future<Map<String, dynamic>?> getById(String id);

  /// 更新信息
  static Future<void> update(String id, Map<String, dynamic> data);

  /// 解除关系（软删除）
  static Future<void> dissolve(String id);

  /// 更新位置（天气查询用）
  static Future<void> updateLocation(String id, {
    required double latitude,
    required double longitude,
    String? city,
    String? district,
  });
}
```

### 4.4 LocalReminderService 设计

```dart
abstract final class LocalReminderService {
  /// 获取某人的提醒配置列表
  static Future<List<Map<String, dynamic>>> getConfigs(String partnerId);

  /// 创建提醒配置
  static Future<Map<String, dynamic>> createConfig(String partnerId, {
    required String category,
    required Map<String, dynamic> config,
  });

  /// 更新配置（启用/禁用/修改参数）
  static Future<void> updateConfig(String id, Map<String, dynamic> data);

  /// 删除配置
  static Future<void> deleteConfig(String id);

  /// 一键提醒（创建日志 + 发本地通知）
  static Future<void> sendReminder(String configId);

  /// 确认提醒
  static Future<void> confirmReminder(String logId);

  /// 获取提醒日志
  static Future<List<Map<String, dynamic>>> getLogs(String configId);

  /// 获取统计数据
  static Future<Map<String, dynamic>> getStats();
}
```

### 4.5 LocalAchievementService 设计

将服务器端 Python 的 4 种解锁逻辑用 Dart 重写：

```dart
abstract final class LocalAchievementService {
  /// 获取所有成就定义
  static Future<List<Map<String, dynamic>>> getAll();

  /// 获取我的成就进度
  static Future<List<Map<String, dynamic>>> getMyProgress();

  /// 更新进度（在每次发送提醒后调用）
  /// [type] = count: 增量 +1
  /// [type] = streak_days: 从今天往回数连续天数
  /// [type] = relationship_days: 关系建立天数
  /// [type] = mutual_reminder_count: 双向提醒最小值
  static Future<void> updateProgress(String achievementId, {
    required String type,
    int increment = 1,
    String? partnerId,
  });

  /// 检查并解锁成就（在提醒操作后批量调用）
  static Future<List<String>> checkAndUnlock();
}
```

**Dart 重写的关键逻辑**：

1. **count 类型**：每次 `sendReminder` 后 `progress += 1`，达到 target 解锁
2. **streak_days 类型**：从本地 `reminder_logs` 表查最近 30 天，逐日检查是否有记录，计算连续天数
3. **relationship_days 类型**：`DateTime.now().difference(partner.createdAt).inDays`
4. **mutual_reminder_count 类型**：单机版简化为"我对每个 partner 的已发送提醒数"（无双向概念），取所有 partner 中的最大值

### 4.6 AiService 设计

```dart
class AiService {
  static const _baseUrl = 'https://api.deepseek.com';
  static const _model = 'deepseek-chat';

  /// 获取用户配置的 API Key
  static Future<String?> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('deepseek_api_key');
  }

  /// AI 关怀建议
  static Future<Map<String, dynamic>> generateSuggestion({
    required String category,
    Map<String, dynamic>? context,
  }) async {
    final key = await _getApiKey();
    if (key == null || key.isEmpty) return _fallbackSuggestion(category);

    try {
      final dio = Dio();
      final response = await dio.post(
        '$_baseUrl/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': _model,
          'temperature': 0.8,
          'max_tokens': 500,
          'messages': [
            {'role': 'system', 'content': _suggestPrompt(category, context)},
          ],
        },
      );
      return _parseSuggestion(response.data);
    } catch (e) {
      return _fallbackSuggestion(category);  // 降级
    }
  }

  /// AI 对话（带历史上下文）
  static Future<String> chat(String userMessage) async {
    final key = await _getApiKey();
    if (key == null || key.isEmpty) return '请先在设置中配置 DeepSeek API Key';

    // 从 chat_history 表读取最近 10 条
    final history = await _getRecentHistory(10);
    history.add({'role': 'user', 'content': userMessage});

    try {
      final dio = Dio();
      final response = await dio.post(
        '$_baseUrl/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': _model,
          'temperature': 0.7,
          'max_tokens': 500,
          'messages': [
            {'role': 'system', 'content': CHAT_SYSTEM_PROMPT},
            ...history,
          ],
        },
      );
      final assistantMessage = response.data['choices'][0]['message']['content'];

      // 保存到 chat_history 表
      await _saveHistory('user', userMessage);
      await _saveHistory('assistant', assistantMessage);

      return assistantMessage;
    } catch (e) {
      return 'AI 暂时无法回复，请检查网络连接和 API Key 配置';
    }
  }
}
```

**Prompt 模板**直接硬编码在客户端，与服务器版完全一致（参见 `server/app/modules/ai/service.py` 中的 `SUGGEST_PROMPTS` 和 `CHAT_SYSTEM_PROMPT`）。

### 4.7 WeatherService 设计

```dart
class WeatherService {
  static const _baseUrl = 'https://devapi.qweather.com/v7';

  static Future<String?> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('qweather_api_key');
  }

  /// 查询当前天气
  static Future<Map<String, dynamic>?> getCurrentWeather(
    double longitude, double latitude,
  ) async {
    final key = await _getApiKey();
    if (key == null) return null;

    final dio = Dio();
    final response = await dio.get(
      '$_baseUrl/weather/now',
      queryParameters: {
        'location': '$longitude,$latitude',
        'key': key,
      },
    );
    if (response.data['code'] == '200') {
      return response.data['now'];
    }
    return null;
  }

  /// 检查天气条件是否满足提醒条件
  static Map<String, dynamic>? checkConditions(
    Map<String, dynamic> weather,
    List<String> conditions,
  ) {
    // 与服务器版逻辑一致：遍历 conditions，匹配 rain/snow/extreme_cold/extreme_heat
    // 返回匹配的条件名和默认消息，或 null
  }
}
```

### 4.8 NotificationService 设计

```dart
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// 初始化（在 main() 中调用）
  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onTap,
    );
  }

  /// 发送即时本地通知
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'taworld_reminders',
      'Ta的提醒',
      channelDescription: 'TaWorld 关怀提醒通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(id, title, body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  /// 定时通知（用于提醒触发）
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    await _plugin.zonedSchedule(
      id, title, body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
```

---

## 五、定时任务方案

### 5.1 WorkManager 替代 APScheduler

服务器端有两个定时任务：
- `weather_check`：每小时检查天气
- `reminder_trigger`：每分钟检查定时提醒

单机版使用 `workmanager` 注册后台任务：

```dart
// main.dart 中注册
await Workmanager().initialize(callbackDispatcher);

// 天气检查：每小时
await Workmanager().registerPeriodicTask(
  'weather_check',
  'weatherCheckTask',
  frequency: const Duration(hours: 1),
  constraints: Constraints(networkType: NetworkType.connected),
);

// 提醒触发：每 15 分钟（Android 最小间隔）
await Workmanager().registerPeriodicTask(
  'reminder_trigger',
  'reminderTriggerTask',
  frequency: const Duration(minutes: 15),
);
```

### 5.2 callbackDispatcher 实现

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case 'weatherCheckTask':
        await _runWeatherCheck();
        break;
      case 'reminderTriggerTask':
        await _runReminderTrigger();
        break;
    }
    return true;
  });
}
```

### 5.3 提醒触发逻辑

从 SQLite 读取所有 `enabled=1` 的 sleep/meal 配置，解析 `config` JSON 中的提醒时间，如果当前时间（精确到分钟）匹配则：
1. 创建 `reminder_logs` 记录
2. 发送本地通知
3. 更新成就进度

去重逻辑：查询今天是否已有相同 `config_id + message` 的日志，有则跳过。

### 5.4 天气检查逻辑

从 SQLite 读取所有 `category=weather AND enabled=1` 的配置，获取对应 partner 的位置，调用 `WeatherService.getCurrentWeather()`，检查条件匹配后：
1. 创建 `reminder_logs` 记录
2. 发送本地通知

---

## 六、前端页面改造

### 6.1 路由变更

```dart
// 移除的路由
// /login       → 改为首次使用引导页（设置昵称）
// /register    → 移除

// 新增的路由
Routes.onboarding = '/onboarding'   // 首次引导（设置昵称 + 配置 API Key）
Routes.addPartner = '/partners/add' // 添加关心的人

// 修改的路由
Routes.relationshipDetail → Routes.partnerDetail  // 改为 partner 详情页
Routes.reminderConfig     → 保持不变，参数改为 partnerId
```

### 6.2 页面改造清单

| 页面 | 改动程度 | 具体改动 |
|------|----------|----------|
| LoginScreen | **重写** | 改为 `OnboardingScreen`：设置昵称 + 可选配置 DeepSeek API Key |
| RegisterScreen | **删除** | 不再需要 |
| HomeScreen._HomeTab | **中等** | 数据源从 API 改为本地 SQLite，问候语保留 |
| HomeScreen._RelationshipsTab | **重写** | 移除邀请码逻辑，改为"添加关心的人"按钮 + 列表 |
| HomeScreen._RemindersTab | **轻微** | 数据源改为本地，结构基本不变 |
| HomeScreen._ProfileTab | **轻微** | 数据源改为本地，增加"设置 API Key"入口 |
| PartnerDetailScreen | **重写** | 替代 RelationshipDetailScreen，编辑对方信息/位置 |
| ReminderConfigScreen | **轻微** | partnerId 替代 relationshipId，数据源改本地 |
| ReminderHistoryScreen | **轻微** | 数据源改本地 |
| AchievementsScreen | **轻微** | 数据源改本地 |
| AiChatScreen | **中等** | 直接调 AiService，增加多轮历史上下文，增加 API Key 检查 |
| SettingsScreen | **完善** | 增加 DeepSeek API Key 配置、和风天气 API Key 配置、暗色模式实际生效 |

### 6.3 新增页面

| 页面 | 路由 | 功能 |
|------|------|------|
| OnboardingScreen | `/onboarding` | 首次使用引导：设置昵称、配置 API Key（可跳过） |
| AddPartnerScreen | `/partners/add` | 添加关心的人：输入昵称、选择关系类型、可选设置位置 |
| ApiKeySetupScreen | `/settings/api-keys` | API Key 管理：DeepSeek Key、和风天气 Key 的填入/修改/测试 |

---

## 七、文件结构变更

### 7.1 新增目录

```
app/lib/
├── data/
│   ├── local/
│   │   ├── database_helper.dart      # SQLite 数据库管理
│   │   └── migrations.dart           # 数据库迁移脚本
│   └── models/
│       ├── user.dart                 # 本地用户模型
│       ├── partner.dart              # 关心的人模型
│       ├── reminder_config.dart      # 提醒配置模型
│       ├── reminder_log.dart         # 提醒日志模型
│       ├── achievement.dart          # 成就模型
│       ├── chat_message.dart         # 对话历史模型
│       └── weather.dart              # 天气数据模型
├── services/
│   ├── local/
│   │   ├── local_user_service.dart
│   │   ├── partner_service.dart
│   │   ├── local_reminder_service.dart
│   │   ├── local_achievement_service.dart
│   │   └── notification_service.dart
│   ├── ai_service.dart               # DeepSeek 直连
│   └── weather_service.dart          # 和风天气直连
├── tasks/
│   └── background_tasks.dart         # WorkManager 回调处理
└── presentation/
    └── screens/
        ├── onboarding/
        │   └── onboarding_screen.dart
        ├── add_partner/
        │   └── add_partner_screen.dart
        └── api_key_setup/
            └── api_key_setup_screen.dart
```

### 7.2 可删除的文件

```
app/lib/
├── core/
│   ├── network/
│   │   └── dio_client.dart           # 保留但简化（移除 Token 拦截器）
│   └── constants/
│       └── api_endpoints.dart        # 移除（不再调用自建后端）
├── services/
│   └── auth_service.dart             # 移除（改为 LocalUserService）
└── presentation/
    └── screens/
        ├── login/                    # 替换为 onboarding
        └── register/                 # 删除
```

---

## 八、Dio 客户端改造

保留 Dio 但大幅简化，仅用于外部 API 调用（DeepSeek、和风天气）：

```dart
Dio createExternalDio({Duration? timeout}) {
  return Dio(BaseOptions(
    connectTimeout: timeout ?? const Duration(seconds: 10),
    receiveTimeout: timeout ?? const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
}
```

移除：Base URL 硬编码、Token 拦截器、401 自动刷新逻辑、`AuthService` 依赖。

---

## 九、Google Fonts 离线方案

`google_fonts` 包在离线环境下无法下载字体。解决方案：

1. 下载 Nunito 字体文件（Regular、Medium、SemiBold、Bold 各一个 .ttf）
2. 放入 `app/assets/fonts/`
3. 在 `pubspec.yaml` 中声明 `fonts` 资源
4. 修改 `TaTheme` 中的 `fontFamily` 引用为本地资源

---

## 十、实施步骤

### Phase 1：基础设施（预计 2-3 天）

1. 添加新依赖（sqflite, uuid, flutter_local_notifications, workmanager, image_picker, permission_handler）
2. 创建 `DatabaseHelper` 和所有表的建表脚本
3. 创建所有 Model 类
4. 成就种子数据插入
5. 改造 Dio 客户端（移除 Token 拦截器）

### Phase 2：服务层（预计 2-3 天）

1. 实现 `LocalUserService`
2. 实现 `PartnerService`
3. 实现 `LocalReminderService`（含定时触发逻辑）
4. 实现 `LocalAchievementService`（4 种解锁逻辑）
5. 实现 `AiService`（DeepSeek 直连）
6. 实现 `WeatherService`（和风天气直连）
7. 实现 `NotificationService`（本地通知）
8. 实现 `BackgroundTasks`（WorkManager 回调）

### Phase 3：页面改造（预计 3-4 天）

1. 创建 `OnboardingScreen`（替代 Login/Register）
2. 创建 `AddPartnerScreen`
3. 创建 `ApiKeySetupScreen`
4. 改造 `HomeScreen` 4 个 Tab
5. 改造 `PartnerDetailScreen`（替代 RelationshipDetailScreen）
6. 改造 `ReminderConfigScreen`
7. 改造 `ReminderHistoryScreen`
8. 改造 `AchievementsScreen`
9. 改造 `AiChatScreen`（增加历史上下文 + API Key 检查）
10. 完善 `SettingsScreen`（API Key 管理 + 暗色模式生效）
11. 更新路由表

### Phase 4：收尾（预计 1-2 天）

1. 内嵌 Nunito 字体文件
2. 配置 Android 通知权限（`AndroidManifest.xml`）
3. 配置 WorkManager 后台任务权限
4. 删除废弃代码（AuthService, ApiEndpoints, LoginScreen, RegisterScreen）
5. `flutter analyze` 验证
6. `flutter build apk --release` 编译测试
7. 真机功能测试

---

## 十一、AndroidManifest.xml 变更

```xml
<!-- 新增权限 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>

<!-- WorkManager 初始化 Provider -->
<provider
    android:name="androidx.startup.InitializationProvider"
    android:authorities="${applicationId}.androidx-startup"
    android:exported="false"
    tools:node="merge">
    <meta-data
        android:name="androidx.work.WorkManagerInitializer"
        android:value="androidx.startup"
        tools:node="remove" />
</provider>
```

---

## 十二、风险与注意事项

### 12.1 WorkManager 限制

Android 对后台任务有严格限制。`workmanager` 的最小执行间隔为 **15 分钟**（系统可能进一步延迟到 30 分钟甚至更长）。这意味着：
- 提醒触发不会精确到分钟，可能有 15-30 分钟延迟
- 天气检查频率受限制

**缓解方案**：对需要精确时间的提醒（如睡觉提醒 22:30），使用 `flutter_local_notifications` 的 `zonedSchedule()` 精确调度，而非依赖 WorkManager 轮询。

### 12.2 DeepSeek API Key 安全

用户自行管理 Key，App 不承担保管责任。在设置页明确提示"请妥善保管 API Key，不要分享给他人"。Key 存储在 SharedPreferences 中，Android 端可通过 `EncryptedSharedPreferences`（后续优化）加密。

### 12.3 单机版的关系模型变化

原服务器版支持两人通过邀请码建立双向关系，单机版简化为"我关心 Ta"的单向模型。这是核心产品逻辑的最大妥协。可以在后续版本中通过局域网蓝牙/WiFi Direct 恢复双向配对。

### 12.4 数据迁移

如果未来需要从单机版升级回服务器版，需设计数据导出功能（JSON 格式），包含所有 partners、reminder_configs、reminder_logs、achievement_progress。
