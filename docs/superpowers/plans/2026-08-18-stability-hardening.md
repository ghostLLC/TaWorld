# TaWorld Stability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复本地提醒时区、备份导入安全与失败回滚，统一本机 JDK/Gradle/代理/Pub Cache 构建入口，并将 Flutter 静态分析和核心数据库、提醒、备份测试收敛到全绿。

**Architecture:** 将设备时区初始化集中到前后台 Isolate 共用服务；将提醒日程计算从通知插件副作用中抽成基于 `TZDateTime` 的纯逻辑；将备份拆成“纯归档校验 + 可注入依赖的恢复事务 + 平台 UI 外壳”；数据库单例增加受控测试注入点。构建环境通过仓库内 PowerShell 包装脚本统一，不写入机器全局配置。

**Tech Stack:** Flutter 3.41.9、Dart 3.11.5、JDK 21、Gradle 8.14、AGP 8.11.1、Kotlin 2.2.20、sqflite、sqflite_common_ffi、flutter_local_notifications、timezone、flutter_timezone、archive、flutter_test。

**Spec:** 本文件即实施规格；基线审计提交为 `78d6d8acf61b2de38c1a2f473e8f17f0388196b9`，仓库路径为 `D:\TaWorld`，Flutter 工程路径为 `D:\TaWorld\app`。

## Global Constraints

- 当前 `master` 与 `origin/master` 同步；实施者必须先创建 `codex/stability-hardening`，不得直接在 `master` 修改业务代码。
- 工作区已有用户修改：根目录 `.gitignore` 增加了 `competition/`。这是用户资产，必须保留，禁止覆盖、回退或混入无关重写。
- 本计划文件由规划对话生成；创建分支后可随首个文档/环境提交一并纳入版本控制。
- 只处理本计划三类稳定性工作。不要顺手修改发布签名、产品 UI、AI 功能、依赖大版本或数据库业务模型。
- 禁止写系统级 `JAVA_HOME`、系统代理或 `C:\Users\LLC\.gradle\gradle.properties`；所有环境变量仅在脚本子进程生命周期内生效。
- 备份导入不得导入或覆盖 `deepseek_api_key`；失败回滚后数据库、可恢复偏好、缓存统计和 API Key 必须与导入前一致。
- 不把 ZIP 条目名拼接为磁盘路径，不允许任意解压。归档内容只按固定白名单文件名读取。
- 严格按 TDD：先写失败测试、确认失败原因正确，再写最小实现，最后重构。
- 每个任务完成后运行该任务的定向测试；每个工作流完成后运行全量 `analyze` 和 `test`。
- 不以“命令退出码为 0”代替结果检查：必须阅读输出，确认没有 analyzer issue、测试跳过、回滚二次异常或 Kotlin 跨盘缓存警告。

---

## Expected Final File Map

### New files

- `D:\TaWorld\tool\taworld.ps1`
- `D:\TaWorld\docs\development_environment.md`
- `D:\TaWorld\app\lib\services\timezone_service.dart`
- `D:\TaWorld\app\lib\services\reminder_schedule_calculator.dart`
- `D:\TaWorld\app\lib\services\backup\backup_archive_codec.dart`
- `D:\TaWorld\app\lib\services\backup\backup_importer.dart`
- `D:\TaWorld\app\test\helpers\test_database.dart`
- `D:\TaWorld\app\test\services\timezone_service_test.dart`
- `D:\TaWorld\app\test\services\reminder_schedule_calculator_test.dart`
- `D:\TaWorld\app\test\data\database_helper_test.dart`
- `D:\TaWorld\app\test\services\backup_archive_codec_test.dart`
- `D:\TaWorld\app\test\services\backup_importer_test.dart`

### Modified files

- `D:\TaWorld\.gitignore`
- `D:\TaWorld\app\pubspec.yaml`
- `D:\TaWorld\app\pubspec.lock`
- `D:\TaWorld\app\android\gradle.properties`
- `D:\TaWorld\app\lib\main.dart`
- `D:\TaWorld\app\lib\services\background_tasks.dart`
- `D:\TaWorld\app\lib\services\notification_service.dart`
- `D:\TaWorld\app\lib\services\reminder_scheduler.dart`
- `D:\TaWorld\app\lib\data\local\database_helper.dart`
- `D:\TaWorld\app\lib\services\data_backup_service.dart`
- `D:\TaWorld\app\lib\presentation\screens\settings\settings_screen.dart`
- `D:\TaWorld\app\lib\presentation\screens\ai_home\ai_home_screen.dart`
- `D:\TaWorld\app\lib\services\ai_memory_service.dart`
- `D:\TaWorld\app\test\widget_test.dart`

---

## Task 0: Establish a Safe Branch and Record the Baseline

**Files:**

- Preserve: `D:\TaWorld\.gitignore`
- Add: `D:\TaWorld\docs\superpowers\plans\2026-08-18-stability-hardening.md`

- [ ] **Step 1: Confirm repository identity and exact baseline**

Run:

```powershell
Set-Location D:\TaWorld
git remote -v
git branch --show-current
git rev-parse HEAD
git rev-parse origin/master
git status --short
```

Expected:

- Repository is `github.com/ghostLLC/TaWorld`.
- Current commit and `origin/master` are both `78d6d8acf61b2de38c1a2f473e8f17f0388196b9` unless the user has explicitly advanced the baseline.
- `.gitignore` is modified and contains `competition/`; the plan file may be untracked.

- [ ] **Step 2: Create the implementation branch without cleaning user changes**

Run:

```powershell
git switch -c codex/stability-hardening
git status --short
```

Do not run `git reset`, `git checkout --`, `git clean`, or stash commands.

- [ ] **Step 3: Capture baseline failures for comparison**

Use the known-good JDK directly for this baseline only:

```powershell
$env:JAVA_HOME = 'D:\AndroidStudio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
Set-Location D:\TaWorld\app
C:\flutter\bin\flutter.bat --version
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
```

Expected baseline:

- Analyzer reports exactly two `prefer_null_aware_operators` issues in `ai_home_screen.dart` and one unused `dart:convert` import in `ai_memory_service.dart`.
- Existing `widget_test.dart` fails because sqflite `databaseFactory` is not initialized on Windows unit tests.

If baseline differs materially, stop and document the delta before implementing; do not blindly tune the plan to hide new failures.

---

## Task 1: Standardize JDK, Gradle, Proxy, and Same-Drive Pub Cache

**Files:**

- Add: `D:\TaWorld\tool\taworld.ps1`
- Add: `D:\TaWorld\docs\development_environment.md`
- Modify: `D:\TaWorld\app\android\gradle.properties`
- Modify: `D:\TaWorld\.gitignore`

- [ ] **Step 1: Remove the repository-wide hard-coded proxy**

Delete only these four lines from `D:\TaWorld\app\android\gradle.properties`:

```properties
systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=7897
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=7897
```

Keep the JVM memory setting and `android.useAndroidX=true`. Do not add `org.gradle.java.home=D:/AndroidStudio/jbr`; a tracked absolute path would break other machines and CI.

- [ ] **Step 2: Ignore generated local caches explicitly**

Ensure the root `.gitignore` retains the user’s `competition/` rule and contains:

```gitignore
# TaWorld local build caches
/.pub-cache/
/app/android/.kotlin/
```

The existing generic `.pub-cache/` rule may already match; the anchored rule documents the intended repository-local cache. Do not remove existing ignore entries.

- [ ] **Step 3: Add one deterministic PowerShell entry point**

Create `D:\TaWorld\tool\taworld.ps1` with these public parameters and semantics:

```powershell
[CmdletBinding()]
param(
    [switch]$Gradle,
    [switch]$UseProxy,
    [string]$ProxyUri = 'http://127.0.0.1:7897',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ToolArgs
)
```

Required behavior:

1. Resolve the repository root from `$PSScriptRoot\..`; never depend on the caller’s current directory.
2. Resolve tool paths from optional overrides first:
   - `TAWORLD_JDK_HOME`, otherwise `D:\AndroidStudio\jbr`.
   - `TAWORLD_FLUTTER_HOME`, otherwise `C:\flutter`.
   - `TAWORLD_PUB_CACHE`, otherwise `D:\TaWorld\.pub-cache`（通过已解析的仓库根目录动态拼接，不硬编码第二份路径）。
3. Validate `java.exe`, `flutter.bat`, `app\pubspec.yaml`, and `app\android\gradlew.bat` before changing directory.
4. Set process-scoped `JAVA_HOME`, prepend JDK `bin` to `Path`, and set `PUB_CACHE` to the resolved same-drive cache.
5. Run `java -version` and reject a JDK whose major version is not 21. Do not accidentally use system Java 8.
6. Default to direct networking. During the child command only, clear `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY`, and set `GRADLE_OPTS=-Djava.net.useSystemProxies=false`.
7. With `-UseProxy`, parse `ProxyUri`, require an explicit host and port, verify the port with `Test-NetConnection`, then set process-scoped `HTTP_PROXY`, `HTTPS_PROXY`, and Java `http/https.proxyHost` and `proxyPort` flags. Abort before Gradle if the proxy port is closed.
8. Preserve prior environment-variable values and restore them in `finally`.
9. Without `-Gradle`, run `flutter.bat @ToolArgs` from `D:\TaWorld\app`.
10. With `-Gradle`, run `gradlew.bat @ToolArgs` from `D:\TaWorld\app\android`.
11. Return the child process exit code via `exit $LASTEXITCODE`.

Use `Push-Location`/`Pop-Location` in `try/finally`. Avoid `Invoke-Expression` and string-built shell commands.

- [ ] **Step 4: Document the supported workflow**

Create `D:\TaWorld\docs\development_environment.md` with:

- Supported versions listed at the top: Flutter 3.41.9, Dart 3.11.5, JDK 21, Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20.
- Why raw `java`/`gradlew` is unsafe on this machine: system `JAVA_HOME` points to Zulu Java 8.
- Why `PUB_CACHE` is repository-local: plugin Kotlin sources must be on the same `D:` drive as Gradle build outputs to avoid Kotlin incremental cache “different roots” failures.
- Default direct-network commands and opt-in proxy examples.
- A warning that proxy `127.0.0.1:7897` is optional and previously caused Java/Gradle TLS handshake failures, so direct mode remains default.
- No instructions that mutate global system settings.

Exact command block:

```powershell
Set-Location D:\TaWorld
.\tool\taworld.ps1 clean
.\tool\taworld.ps1 pub get
.\tool\taworld.ps1 analyze
.\tool\taworld.ps1 test
.\tool\taworld.ps1 build apk --release
.\tool\taworld.ps1 -Gradle --version

# Only when direct access is unavailable and the local proxy is confirmed healthy
.\tool\taworld.ps1 -UseProxy -ProxyUri http://127.0.0.1:7897 pub get
```

- [ ] **Step 5: Rehydrate dependencies onto the same drive**

Run:

```powershell
Set-Location D:\TaWorld
.\tool\taworld.ps1 clean
.\tool\taworld.ps1 pub get
```

Then verify `D:\TaWorld\app\.dart_tool\package_config.json` contains `D:/TaWorld/.pub-cache/` URIs for hosted packages and no URI rooted at `C:/Users/LLC/AppData/Local/Pub/Cache/`.

- [ ] **Step 6: Verify both Flutter and Gradle see JDK 21**

Run:

```powershell
.\tool\taworld.ps1 doctor -v
.\tool\taworld.ps1 -Gradle --version
.\tool\taworld.ps1 -Gradle help --no-daemon
```

Expected:

- Gradle JVM is the Android Studio JBR 21.
- Direct dependency resolution succeeds without the former forced proxy.
- Output contains no Kotlin incremental cache “different roots” or “Could not close incremental caches” messages.

- [ ] **Step 7: Commit the environment work**

```powershell
git add .gitignore app/android/gradle.properties tool/taworld.ps1 docs/development_environment.md docs/superpowers/plans/2026-08-18-stability-hardening.md
git commit -m "chore: standardize local Flutter build environment"
```

Before committing, inspect `git diff --cached`; confirm the existing `competition/` ignore rule remains intact.

---

## Task 2: Add Testable Database Lifecycle and Core Database Tests

**Files:**

- Modify: `D:\TaWorld\app\pubspec.yaml`
- Modify: `D:\TaWorld\app\pubspec.lock`
- Modify: `D:\TaWorld\app\lib\data\local\database_helper.dart`
- Add: `D:\TaWorld\app\test\helpers\test_database.dart`
- Add: `D:\TaWorld\app\test\data\database_helper_test.dart`

- [ ] **Step 1: Add the Windows-compatible SQLite test dependency**

Run through the standardized wrapper:

```powershell
Set-Location D:\TaWorld
.\tool\taworld.ps1 pub add --dev sqflite_common_ffi:^2.4.0
```

Do not move `sqflite_common_ffi` into production dependencies.

- [ ] **Step 2: Write the database tests first**

Create `test/helpers/test_database.dart` around this contract:

```dart
Future<void> openTestDatabase({String path = inMemoryDatabasePath});
Future<void> closeTestDatabase();
```

The helper must call `sqfliteFfiInit()`, inject `databaseFactoryFfi` and the requested path into `DatabaseHelper`, and reset the singleton in teardown.

Create `test/data/database_helper_test.dart` with independent `setUp`/`tearDown` and these cases:

1. A fresh v4 database creates exactly the 11 application tables:
   `users`, `partners`, `reminder_configs`, `reminder_logs`, `achievements`, `user_achievements`, `chat_history`, `ai_pending_messages`, `ai_wiki_facts`, `ai_conversation_summaries`, `conversation_chunks`.
2. `PRAGMA user_version` equals `DatabaseHelper.schemaVersion`.
3. Achievement seed count equals `kSeedAchievements.length`; do not hard-code a duplicate numeric truth.
4. `PRAGMA foreign_keys` is `1`.
5. Deleting a partner cascades through `reminder_configs` and `reminder_logs` after inserting a complete partner/config/log fixture.
6. `DatabaseHelper.close()` is idempotent and does not open a previously unopened database merely to close it.
7. A file database created at schema v1 upgrades through v2/v3/v4 and contains all new AI tables/indexes after `DatabaseHelper` opens it.

When checking table names, query `sqlite_master` with `type = 'table'` and exclude names starting with `sqlite_`; compare the resulting application-table set, not database-engine internals.

For the migration test, create a real temporary `.db` path with `Directory.systemTemp.createTemp`, open it through `databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: createVersionOneFixture))`, close it, then inject that path and open through `DatabaseHelper`. `createVersionOneFixture` must create the original v1 tables needed by the test; it must not pre-create v2–v4 AI tables. Always delete only the exact temp directory in teardown.

- [ ] **Step 3: Run the tests and confirm the intended failure**

```powershell
.\tool\taworld.ps1 test test/data/database_helper_test.dart
```

Expected failure: `DatabaseHelper` has no factory/path injection and `close()` opens the singleton. Do not weaken assertions.

- [ ] **Step 4: Add a narrow production-safe injection seam**

Refactor `DatabaseHelper` with these public/testing members:

```dart
static int get schemaVersion => _dbVersion;

static DatabaseFactory? _databaseFactoryOverride;
static String? _databasePathOverride;

static Future<void> configureForTesting({
  required DatabaseFactory factory,
  required String path,
});

static Future<void> resetForTesting();
```

Implementation rules:

- Production behavior remains `databaseFactory` + `getDatabasesPath()` + `taworld.db`.
- `_initDatabase()` must call the selected factory’s `openDatabase` with `OpenDatabaseOptions(version: _dbVersion, onConfigure: _onConfigure, onCreate: _onCreate, onUpgrade: _onUpgrade)`; extract the existing foreign-key callback to `_onConfigure` if needed, without changing its behavior.
- `getDatabasePath()` returns the injected path when configured, otherwise the production path.
- `configureForTesting` first closes any open instance, then stores both overrides. It must never be called by production code.
- `resetForTesting` closes the instance if present, sets it to null, then clears overrides.
- `close()` checks `_database`; if null it returns immediately. It must not call the `database` getter.
- `forceReopen()` uses `close()` then opens once through `database`.

Do not expose `_onCreate`/`_onUpgrade` publicly just for tests; exercise them by opening databases.

- [ ] **Step 5: Make all database tests pass**

```powershell
.\tool\taworld.ps1 test test/data/database_helper_test.dart
```

Expected: all database cases pass with no temp files left behind.

- [ ] **Step 6: Commit the database test seam**

```powershell
git add app/pubspec.yaml app/pubspec.lock app/lib/data/local/database_helper.dart app/test/helpers/test_database.dart app/test/data/database_helper_test.dart
git commit -m "test: cover the local database lifecycle"
```

---

## Task 3: Initialize the Real Device Timezone in Foreground and Background Isolates

**Files:**

- Modify: `D:\TaWorld\app\pubspec.yaml`
- Modify: `D:\TaWorld\app\pubspec.lock`
- Add: `D:\TaWorld\app\lib\services\timezone_service.dart`
- Modify: `D:\TaWorld\app\lib\main.dart`
- Modify: `D:\TaWorld\app\lib\services\background_tasks.dart`
- Modify: `D:\TaWorld\app\lib\services\reminder_scheduler.dart`
- Add: `D:\TaWorld\app\test\services\timezone_service_test.dart`

- [ ] **Step 1: Add the platform timezone dependency**

```powershell
Set-Location D:\TaWorld
.\tool\taworld.ps1 pub add flutter_timezone:^5.1.0
```

Keep `timezone`; `flutter_timezone` discovers the device’s IANA identifier, while `timezone` supplies the location database and `TZDateTime` types.

- [ ] **Step 2: Write service tests before implementation**

Define the intended API in tests:

```dart
typedef TimezoneIdentifierLoader = Future<String> Function();

abstract final class TimezoneService {
  static bool get isInitialized;

  static Future<String> initialize({
    TimezoneIdentifierLoader? identifierLoader,
  });

  @visibleForTesting
  static void resetForTesting();
}
```

Test cases:

1. Injecting `Asia/Shanghai` sets `tz.local.name` to `Asia/Shanghai` and returns that identifier.
2. Injecting `America/Los_Angeles` sets the correct location and proves a winter date and summer date have different UTC offsets.
3. Injecting an invalid identifier throws a descriptive `StateError` containing the invalid identifier; it must not silently fall back to UTC.
4. `isInitialized` is true only after `tz.setLocalLocation` succeeds; invalid initialization leaves it false.
5. Each test calls `TimezoneService.resetForTesting()` in teardown; that method sets `tz.local` to `tz.UTC` and the internal initialized flag to false so global timezone state cannot leak across tests.

- [ ] **Step 3: Run and confirm the missing-service failure**

```powershell
.\tool\taworld.ps1 test test/services/timezone_service_test.dart
```

- [ ] **Step 4: Implement the single timezone initialization path**

Create `timezone_service.dart` with this sequence:

```dart
tz_data.initializeTimeZones();
final identifier = identifierLoader != null
    ? await identifierLoader()
    : (await FlutterTimezone.getLocalTimezone()).identifier;
final location = tz.getLocation(identifier);
tz.setLocalLocation(location);
return identifier;
```

Set the internal initialized flag to false before discovery and true only after `tz.setLocalLocation` succeeds. Catch the invalid-location error and rethrow a `StateError('Unsupported device timezone: $identifier')` with `Error.throwWithStackTrace` so the original stack remains available for logging. Do not catch platform discovery failures as UTC.

- [ ] **Step 5: Replace both old initialization call sites**

In `main.dart`:

- Remove `timezone/data/latest.dart` import.
- Call `await TimezoneService.initialize()` before initializing notifications and before `ReminderScheduler.scheduleAll()`.
- Wrap background-service initialization in `try/catch` with `dart:developer` logging so a notification subsystem failure does not leave the app on a blank screen; `runApp(const TaWorldApp())` must still execute.
- Do not call `ReminderScheduler.scheduleAll()` when timezone initialization failed.
- At the start of `ReminderScheduler.scheduleAll()`, check `TimezoneService.isInitialized` before `cancelAll()`. If false, log and return without canceling or creating notifications. This also protects the app lifecycle `resumed` callback in `app.dart` after a failed startup initialization.

In `background_tasks.dart`:

- Remove the direct `tz_data.initializeTimeZones()` import/call.
- Call `await TimezoneService.initialize()` inside the `executeTask` `try` block, before the task switch.
- On timezone discovery failure, log it and return `false` from the WorkManager callback so the task can be retried; do not schedule using UTC.

- [ ] **Step 6: Run timezone tests and analyzer**

```powershell
.\tool\taworld.ps1 test test/services/timezone_service_test.dart
.\tool\taworld.ps1 analyze
```

Analyzer may still report the three known pre-existing issues, but no new issue is allowed.

- [ ] **Step 7: Commit timezone initialization**

```powershell
git add app/pubspec.yaml app/pubspec.lock app/lib/services/timezone_service.dart app/lib/main.dart app/lib/services/background_tasks.dart app/lib/services/reminder_scheduler.dart app/test/services/timezone_service_test.dart
git commit -m "fix: initialize the device timezone before scheduling"
```

---

## Task 4: Extract Deterministic, DST-Safe Reminder Scheduling and Test It

**Files:**

- Add: `D:\TaWorld\app\lib\services\reminder_schedule_calculator.dart`
- Modify: `D:\TaWorld\app\lib\services\notification_service.dart`
- Modify: `D:\TaWorld\app\lib\services\reminder_scheduler.dart`
- Add: `D:\TaWorld\app\test\services\reminder_schedule_calculator_test.dart`

- [ ] **Step 1: Specify the pure calculation types in tests**

Use this API shape:

```dart
class ReminderOccurrence {
  final int notificationId;
  final String title;
  final String body;
  final String payload;
  final tz.TZDateTime scheduledTime;
}

abstract final class ReminderScheduleCalculator {
  static List<ReminderOccurrence> build({
    required ReminderConfig config,
    required String partnerName,
    required tz.TZDateTime now,
    int occurrenceCount = 7,
  });
}
```

The result is pure data. It must not touch SQLite, SharedPreferences, notification plugins, `DateTime.now()`, or platform APIs.

- [ ] **Step 2: Add deterministic behavior tests**

Initialize timezone data once in the test file and construct `now` with an explicit `tz.Location`. Cover:

1. Sleep reminder before today’s trigger produces today plus the next six calendar days.
2. Sleep reminder after today’s trigger starts tomorrow.
3. Equality is not “past”: if `scheduledTime == now`, today remains included, preserving existing behavior.
4. Advance minutes crossing midnight maps a `00:10` target with 30-minute advance to `23:40` on the preceding calendar date.
5. Month/year boundary produces valid next dates.
6. Meal config emits seven occurrences per valid meal, with correct title/body/payload and unique IDs within the returned set.
7. Empty meal list returns an empty list.
8. Weather config emits seven 08:00 occurrences.
9. Custom config returns an empty list.
10. Invalid `HH:mm` values such as `25:90`, non-numeric strings, malformed fields, non-integer advances, and negative advances are rejected consistently. Preferred contract: return no occurrences for that invalid item rather than silently substitute a different time.
11. `America/Los_Angeles` occurrences remain at the configured wall-clock time across a DST transition. Build each calendar occurrence from year/month/day/hour/minute; do not repeatedly add `Duration(days: 1)` to the previous zoned instant.

Do not assert a hard-coded numeric hash value. Assert IDs are positive, within signed 32-bit range, stable for two identical calls in one process, and unique in one schedule batch.

- [ ] **Step 3: Run and confirm the missing-calculator failure**

```powershell
.\tool\taworld.ps1 test test/services/reminder_schedule_calculator_test.dart
```

- [ ] **Step 4: Implement the pure calculator**

Rules:

- Use `now.location` for every occurrence.
- Parse time with a private strict parser that accepts only `00:00` through `23:59`.
- Require `advance_minutes` to be an integer in `0..1440`; invalid values skip the relevant reminder item.
- For each target calendar day, construct `tz.TZDateTime(location, year, month, day + offset, hour, minute)` and then subtract advance minutes.
- Locate the first occurrence whose scheduled instant is not before `now`, then generate exactly `occurrenceCount` calendar occurrences.
- Preserve the existing Chinese titles, bodies, and payload format `configId:${config.id}`.
- Preserve the existing positive signed-32-bit notification ID range.

- [ ] **Step 5: Make NotificationService accept an already-zoned instant**

Change `NotificationService.schedule` from `DateTime scheduledTime` to `tz.TZDateTime scheduledTime`.

- Compare against `tz.TZDateTime.now(tz.local)`.
- Pass `scheduledTime` directly to `zonedSchedule`; remove `tz.TZDateTime.from(scheduledTime, tz.local)`.
- This prevents a second implicit timezone conversion.

- [ ] **Step 6: Reduce ReminderScheduler to side-effect orchestration**

Replace the private category-specific date arithmetic with:

```dart
final occurrences = ReminderScheduleCalculator.build(
  config: config,
  partnerName: partnerName,
  now: tz.TZDateTime.now(tz.local),
);
for (final occurrence in occurrences) {
  await NotificationService.schedule(
    id: occurrence.notificationId,
    title: occurrence.title,
    body: occurrence.body,
    scheduledTime: occurrence.scheduledTime,
    payload: occurrence.payload,
  );
  await LocalReminderService.createScheduledLog(
    configId: config.id,
    partnerId: config.partnerId,
    message: occurrence.body,
    scheduledTime: occurrence.scheduledTime,
  );
}
```

Retain `scheduleAll`, partner lookup, cancellation strategy, notification scheduling, and scheduled-log creation. Remove only duplicated date/category calculation now covered by the pure calculator.

- [ ] **Step 7: Run reminder, timezone, and database tests**

```powershell
.\tool\taworld.ps1 test test/services/reminder_schedule_calculator_test.dart
.\tool\taworld.ps1 test test/services/timezone_service_test.dart
.\tool\taworld.ps1 test test/data/database_helper_test.dart
```

- [ ] **Step 8: Commit reminder scheduling**

```powershell
git add app/lib/services/reminder_schedule_calculator.dart app/lib/services/notification_service.dart app/lib/services/reminder_scheduler.dart app/test/services/reminder_schedule_calculator_test.dart
git commit -m "refactor: make reminder scheduling deterministic"
```

---

## Task 5: Build a Strict Backup Archive Codec

**Files:**

- Add: `D:\TaWorld\app\lib\services\backup\backup_archive_codec.dart`
- Add: `D:\TaWorld\app\test\services\backup_archive_codec_test.dart`
- Modify: `D:\TaWorld\app\lib\services\data_backup_service.dart` (only relocate/import `BackupInfo` in this task; behavior changes remain in Task 6)

- [ ] **Step 1: Define explicit archive-domain types**

Implement tests against this public shape:

```dart
class ValidatedBackupArchive {
  final BackupInfo info;
  final Uint8List databaseBytes;
  final Map<String, Object?> preferences;
}

class BackupFormatException implements Exception {
  final String message;
}

abstract final class BackupArchiveCodec {
  static const int maxArchiveBytes = 128 * 1024 * 1024;
  static const int maxDatabaseBytes = 256 * 1024 * 1024;
  static const int maxMetadataBytes = 1024 * 1024;

  static ValidatedBackupArchive decode(Uint8List bytes);
}
```

Move the existing `BackupInfo` class from `data_backup_service.dart` into `backup_archive_codec.dart`, including its `summary` getter, and import it back into `DataBackupService`. The codec must not import `DataBackupService`; this keeps dependency direction one-way and both files compilable at the end of this task.

- [ ] **Step 2: Write malicious and malformed archive tests first**

Use `Archive`/`ZipEncoder` in test helpers to generate fixtures in memory. Test:

1. A valid archive with `manifest.json`, `database.db`, and optional `preferences.json` decodes.
2. Missing manifest or database is rejected.
3. Duplicate `manifest.json`, duplicate `database.db`, or duplicate preferences are rejected.
4. Any entry containing `/`, `\`, `..`, a drive prefix such as `C:`, or an absolute path is rejected, including `../evil.db`, `subdir/database.db`, and `C:\evil`.
5. Directory entries and unknown file names are rejected. Allowed names are exactly `manifest.json`, `database.db`, and `preferences.json`.
6. Archive byte size, database uncompressed size, manifest size, and preference size limits are enforced before reading entry content wherever the archive API permits.
7. Invalid UTF-8, invalid JSON, non-object JSON, invalid `created_at`, invalid/non-integer `schema_version`, and non-integer `row_counts` values are rejected.
8. `app_name != TaWorld` is rejected.
9. Schema version `< 1` or `> DatabaseHelper.schemaVersion` is rejected before any database lifecycle call.
10. Empty database bytes are rejected.
11. Preferences containing unsupported value types (nested maps/lists/null) are rejected or ignored according to one documented contract. Preferred: reject the malformed preference entry so import behavior is deterministic.

Tests must assert `BackupFormatException`, not generic `Exception` text only.

- [ ] **Step 3: Run and confirm failure**

```powershell
.\tool\taworld.ps1 test test/services/backup_archive_codec_test.dart
```

- [ ] **Step 4: Implement whitelist-only decoding**

Required sequence:

1. Reject empty input and `bytes.length > maxArchiveBytes` before ZIP decoding.
2. Decode with archive integrity verification enabled when supported by the installed `archive` API.
3. Iterate entries exactly once to validate type, canonical name, duplicates, and declared uncompressed size.
4. Never create a file path from `entry.name`; the codec is memory-only.
5. Decode required files only after the entire entry list passes structural validation.
6. Strictly parse manifest fields; do not substitute `DateTime.now()` for invalid metadata.
7. Copy database bytes into a new `Uint8List` so returned data is not backed by mutable archive storage.
8. Return an empty preference map when `preferences.json` is absent.

Even though the implementation never extracts arbitrary entries, retain path/name rejection as defense in depth and to make future refactors safe.

- [ ] **Step 5: Make codec tests pass and commit**

```powershell
.\tool\taworld.ps1 test test/services/backup_archive_codec_test.dart
git add app/lib/services/backup/backup_archive_codec.dart app/lib/services/data_backup_service.dart app/test/services/backup_archive_codec_test.dart
git commit -m "fix: strictly validate backup archives"
```

---

## Task 6: Implement Atomic-Style Backup Import with Failure Rollback

**Files:**

- Add: `D:\TaWorld\app\lib\services\backup\backup_importer.dart`
- Add: `D:\TaWorld\app\test\services\backup_importer_test.dart`
- Modify: `D:\TaWorld\app\lib\services\data_backup_service.dart`
- Modify: `D:\TaWorld\app\lib\presentation\screens\settings\settings_screen.dart`

- [ ] **Step 1: Define an injectable import boundary**

Use a small dependency object so failure stages can be tested without platform channels:

```dart
class BackupImportDependencies {
  final String databasePath;
  final Directory temporaryRoot;
  final SharedPreferences preferences;
  final DatabaseFactory databaseFactory;
  final Future<void> Function() closeDatabase;
  final Future<Database> Function() reopenDatabase;
  final Future<void> Function(String stage)? afterStage;
}

class BackupImportException implements Exception {
  final String message;
  final Object cause;
  final Object? rollbackCause;
}

class BackupImporter {
  const BackupImporter();

  Future<void> importBytes(
    Uint8List zipBytes,
    BackupImportDependencies dependencies,
  );
}
```

Keep the class free of `file_picker`, `file_saver`, `share_plus`, and `path_provider`. `DataBackupService` remains the production adapter that supplies those dependencies.

- [ ] **Step 2: Write rollback tests before the importer**

In `backup_importer_test.dart`:

- Use `sqflite_common_ffi`, a unique temporary directory per test, and a real file-backed SQLite live database.
- Use `SharedPreferences.setMockInitialValues` before obtaining the instance.
- Build ZIP fixtures with a valid TaWorld manifest and SQLite bytes produced by an actual temporary database, not arbitrary text.
- Always close handles and delete only the exact per-test temp directory in teardown.

Required cases:

1. Valid import replaces old database rows, migrates an older supported schema to current, restores only allowed preferences, resets `cache_hit_tokens` and `cache_miss_tokens` to zero, and preserves `deepseek_api_key` exactly.
2. An archive preference named `deepseek_api_key` is ignored even if maliciously present.
3. Unknown preference keys are ignored; they are never written.
4. Invalid archive validation fails before `closeDatabase` is called and leaves the live DB byte-for-byte unchanged.
5. Corrupt/non-SQLite `database.db` fails staging validation before closing the live DB.
6. `PRAGMA quick_check` result other than `ok` fails before live replacement.
7. Injected failure immediately after live database replacement restores original database rows and every preference key the importer could have changed.
8. Injected `reopenDatabase`/migration failure restores the original database and preferences, then reopens the restored database.
9. Injected preference write failure after a valid DB reopen rolls back both database and already-written preferences.
10. If rollback itself fails, `BackupImportException.rollbackCause` is non-null and the original import failure remains available as `cause`.
11. Temporary staging and `.incoming` files are removed on success and failure.
12. The persistent `.pre_import_backup` contains the pre-import live database after success, providing a manual safety copy.

Use `afterStage` to inject exact failures without test-only globals. Define constants for `validated`, `databaseReplaced`, `databaseReopened`, `preferencesApplied`, and emit `preferenceApplied:$key` immediately after every preference mutation. Production passes no callback.

- [ ] **Step 3: Run and confirm intended failures**

```powershell
.\tool\taworld.ps1 test test/services/backup_importer_test.dart
```

- [ ] **Step 4: Implement the transaction in this exact order**

`BackupImporter.importBytes` must:

1. Call `BackupArchiveCodec.decode` before closing the live database.
2. Create a unique child directory via `temporaryRoot.createTemp('taworld_import_')`; never reuse a fixed `import_temp` directory.
3. Write only `validated.databaseBytes` to a fixed staging filename such as `database.staged`; no ZIP entry names reach the filesystem.
4. Open the staged database read-only with `singleInstance: false`, run `PRAGMA quick_check`, read `PRAGMA user_version`, require `1..DatabaseHelper.schemaVersion`, then close it.
5. Snapshot all preferences the importer may change, including both the value and whether the key existed. The set is the restore whitelist plus `cache_hit_tokens` and `cache_miss_tokens`. Capture `deepseek_api_key` for an explicit preservation assertion even though it is never written.
6. Call `closeDatabase` only after archive and staged-database validation have passed.
7. Copy the current live database to `${dependencies.databasePath}.pre_import_backup`. If no live database exists, record that fact for rollback.
8. Copy staged bytes to `${dependencies.databasePath}.incoming`; ensure the parent directory exists.
9. Remove stale SQLite sidecars for the closed live DB (`-wal`, `-shm`, `-journal`), replace the live file from the fixed `.incoming` path, then invoke the `databaseReplaced` hook.
10. Call `reopenDatabase`; this performs supported schema migration and returns the reopened singleton handle. Query that returned `Database` and require `PRAGMA quick_check == ok` and `user_version == DatabaseHelper.schemaVersion` before touching preferences. Do not open a second live handle just to verify it.
11. Apply only the explicit restore whitelist:
    `theme_mode`, `palette_id`, `push_enabled`, `ai_proactive_enabled`, `last_dream_time`, `last_proactive_time`.
12. Accept only String, bool, int, and double preference values. Do not import lists, objects, nulls, unknown keys, `last_backup_time`, or `deepseek_api_key`.
13. Set `cache_hit_tokens=0` and `cache_miss_tokens=0` only after the DB is valid.
14. Assert/read back that `deepseek_api_key` still equals its pre-import value, then invoke `preferencesApplied`.
15. On success, retain `.pre_import_backup` but remove `.incoming` and the unique staging directory.
16. On any failure after mutation begins: close the imported DB; restore the original live DB or remove it if none existed; remove sidecars; restore every snapshotted preference including absence via `remove`; restore the API key if unexpectedly changed; reopen the restored database; clean temporary artifacts; throw `BackupImportException` preserving both import and optional rollback failures.
17. In `finally`, perform best-effort cleanup of only the exact staging directory and `.incoming` path. Never let cleanup replace the primary exception.

Do not treat file copy alone as validation. Do not update preferences before the imported DB is reopened and checked.

- [ ] **Step 5: Refactor DataBackupService into a platform adapter**

Changes:

- Remove arbitrary ZIP extraction and `_backupCurrentData()` preference-file logic.
- Make `_currentSchemaVersion` use `DatabaseHelper.schemaVersion` instead of duplicating the number 4.
- Reuse `BackupArchiveCodec.decode` in both `validateBackup` and `importBackup` so confirmation and actual import enforce identical rules.
- `validateBackup` reads bytes and returns `.info`; it performs no database close or write.
- `importBackup` reads bytes, resolves `DatabaseHelper.getDatabasePath()`, `getTemporaryDirectory()`, `SharedPreferences.getInstance()`, and production `databaseFactory`, then delegates to `BackupImporter`.
- Supply `reopenDatabase` as `() async { await DatabaseHelper.forceReopen(); return DatabaseHelper.database; }`, ensuring migration and post-open verification use the application singleton.
- Keep export behavior, but keep its preference whitelist as one shared constant used by export and import.
- Ensure export reopens the database in `finally` if any step after `DatabaseHelper.close()` fails. Export must not leave the app’s singleton closed.

- [ ] **Step 6: Correct the settings copy**

In `settings_screen.dart`:

- Replace “API Key 需要重新配置” with wording that API Key remains local and is not imported.
- On `BackupImportException` with successful rollback, show a message equivalent to “导入失败，原数据已恢复”。
- If `rollbackCause` is present, show a stronger message telling the user not to continue editing data and to retain the `.pre_import_backup`; log technical details with stack traces, but do not display paths or API key values.
- Do not expose exception internals or secrets in the UI.

- [ ] **Step 7: Run backup tests and regression tests**

```powershell
.\tool\taworld.ps1 test test/services/backup_archive_codec_test.dart
.\tool\taworld.ps1 test test/services/backup_importer_test.dart
.\tool\taworld.ps1 test test/data/database_helper_test.dart
```

- [ ] **Step 8: Commit transactional backup import**

```powershell
git add app/lib/services/backup/backup_importer.dart app/test/services/backup_importer_test.dart app/lib/services/data_backup_service.dart app/lib/presentation/screens/settings/settings_screen.dart
git commit -m "fix: rollback failed backup imports"
```

---

## Task 7: Clear Static Analysis and Repair the Widget Smoke Test

**Files:**

- Modify: `D:\TaWorld\app\lib\presentation\screens\ai_home\ai_home_screen.dart`
- Modify: `D:\TaWorld\app\lib\services\ai_memory_service.dart`
- Modify: `D:\TaWorld\app\test\widget_test.dart`

- [ ] **Step 1: Apply only the three known analyzer fixes**

In `ai_home_screen.dart`, replace both explicit null conditionals:

```dart
final city = rawCity?.trim().replaceAll(RegExp(r'[市]$'), '');
```

and:

```dart
final city = rawCity?.trim().replaceAll(RegExp(r'[市县区]$'), '');
```

In `ai_memory_service.dart`, remove the unused:

```dart
import 'dart:convert';
```

Do not reformat or alter the surrounding AI tool behavior.

- [ ] **Step 2: Repair the existing widget test with the shared DB helper**

Update `widget_test.dart` so it:

- Calls `TestWidgetsFlutterBinding.ensureInitialized()` once.
- Opens a fresh FFI test database in `setUp` using `openTestDatabase()`.
- Closes/resets it in `tearDown`.
- Pumps `const TaWorldApp()` and waits with a bounded series of `pump` calls rather than an unbounded `pumpAndSettle` if animations repeat.
- Retains a meaningful smoke assertion for the initial screen instead of deleting the test or asserting only that no exception occurred.

If the app accesses SharedPreferences in the initial route, call `SharedPreferences.setMockInitialValues({})` before pumping.

- [ ] **Step 3: Run the repaired widget test**

```powershell
.\tool\taworld.ps1 test test/widget_test.dart
```

If another platform plugin fails, inject/mock that boundary in test setup; do not remove production initialization or skip the test.

- [ ] **Step 4: Require zero analyzer findings**

```powershell
.\tool\taworld.ps1 analyze
```

Expected exact success signal: `No issues found!`

Do not add broad `ignore_for_file`, weaken `analysis_options.yaml`, or suppress lints to reach zero.

- [ ] **Step 5: Run the complete test suite**

```powershell
.\tool\taworld.ps1 test
```

Expected: all tests pass, none skipped, no unhandled asynchronous errors after the test runner reports completion.

- [ ] **Step 6: Commit analyzer and smoke-test fixes**

```powershell
git add app/lib/presentation/screens/ai_home/ai_home_screen.dart app/lib/services/ai_memory_service.dart app/test/widget_test.dart
git commit -m "test: restore a clean Flutter quality gate"
```

---

## Task 8: Full Verification and Risk-Focused Manual Checks

**Files:**

- No planned source changes. Fix only evidence-backed defects found by verification, in a separate commit.

- [ ] **Step 1: Run clean-room quality gates from the standardized entry point**

```powershell
Set-Location D:\TaWorld
.\tool\taworld.ps1 clean
.\tool\taworld.ps1 pub get
.\tool\taworld.ps1 analyze
.\tool\taworld.ps1 test
.\tool\taworld.ps1 build apk --release
```

Acceptance:

- Analyze: `No issues found!`
- Tests: all pass, no skips.
- Release APK build succeeds.
- No source path under `C:\Users\LLC\AppData\Local\Pub\Cache` appears in Kotlin incremental-cache warnings.
- No proxy TLS handshake failure occurs in default direct mode.

- [ ] **Step 2: Verify generated-file hygiene**

```powershell
git status --short --ignored
```

Confirm `.pub-cache`, `app/build`, `.dart_tool`, and `app/android/.kotlin` are ignored and no generated artifacts are staged. Do not use broad `git clean`.

- [ ] **Step 3: Perform Android timezone smoke checks**

On an emulator or device:

1. Set timezone to `Asia/Shanghai`, create a reminder 5–10 minutes ahead, restart the app, and confirm the pending scheduled time matches local wall time.
2. Change device timezone to another IANA zone, relaunch so `TimezoneService` reinitializes and `scheduleAll()` cancels/rebuilds notifications, then confirm the new local scheduled time.
3. Trigger the notification-renew WorkManager task if tooling permits, or inspect logs on its next run, and confirm the background Isolate reports the same IANA identifier rather than UTC.

Record device model, Android version, timezone, expected time, and observed time. Do not claim this check passed without device evidence.

- [ ] **Step 4: Perform backup safety smoke checks with disposable data**

1. Create identifiable disposable rows and a test API Key marker.
2. Export a valid backup.
3. Change local data, then import the backup; verify database data restored and API Key marker remained the newer local value.
4. Attempt a corrupt ZIP and confirm current data remains unchanged.
5. Use a test-only/debug fixture that fails after replacement and confirm UI reports that original data was restored.
6. Confirm no `taworld_import_*` staging directory or `.incoming` file remains.

Never use the user’s only real backup as a destructive test fixture.

- [ ] **Step 5: Review branch diff for scope and secrets**

```powershell
git diff origin/master...HEAD --stat
git diff origin/master...HEAD
git status --short
```

Review checklist:

- No API key, local absolute backup path, signing secret, or user data is committed.
- No release signing or unrelated product behavior changed.
- Root `.gitignore` still contains `competition/`.
- Proxy is opt-in and process-scoped.
- Backup import has no `entry.name`-derived write path.
- All catch paths preserve the primary exception and attempt database reconnection.

- [ ] **Step 6: Commit only verification-driven corrections**

If verification required fixes, commit them separately:

```powershell
git status --short
# Review the status, then run git add with only the concrete files changed by that verified correction.
git commit -m "fix: address stability verification findings"
```

If no fix was needed, do not create an empty commit.

- [ ] **Step 7: Produce the Luna execution report**

Report:

- Branch and final commit SHA.
- Each commit and its purpose.
- Exact analyze/test/build command results and durations.
- Automated test counts grouped by database, timezone/reminder, backup, widget.
- Whether physical/emulator timezone and backup smoke checks were actually performed.
- Any remaining risk, especially Android OEM background scheduling behavior or rollback failure that cannot be simulated outside a device.
- Final `git status --short` output.

---

## Definition of Done

- [ ] `codex/stability-hardening` exists; `master` was not directly modified by the executor.
- [ ] Flutter and Gradle commands use JDK 21 through `tool/taworld.ps1`.
- [ ] The tracked Gradle config contains no hard-coded proxy.
- [ ] The effective Pub cache is on `D:` and Kotlin emits no cross-root incremental-cache failure.
- [ ] Foreground and WorkManager background Isolates set `tz.local` from the device IANA identifier before scheduling.
- [ ] Reminder occurrences are deterministic, use `TZDateTime`, handle cross-midnight/calendar/DST cases, and retain existing user-facing copy.
- [ ] Backup ZIP entries are whitelist-only, size/schema/metadata checked, and never arbitrarily extracted.
- [ ] Invalid archives and invalid staged databases do not close or alter the live database.
- [ ] Any post-mutation failure restores the original database and all affected preferences; API Key is preserved.
- [ ] `flutter analyze` prints `No issues found!` without lint suppression.
- [ ] Existing widget test passes with a real FFI SQLite test setup.
- [ ] Database, timezone/reminder, archive validation, and rollback tests all pass.
- [ ] Clean release APK build succeeds through the standardized wrapper.
- [ ] No generated artifacts, local caches, credentials, or unrelated edits are staged.

## Explicitly Deferred Risks

These are outside this implementation and must not be silently folded in:

- Release APK still uses debug signing.
- There is no CI workflow yet; this plan creates a repeatable local gate only.
- Android/OEM exact-alarm and WorkManager delivery can still be affected by Xiaomi/HyperOS battery policies; this plan fixes timezone correctness, not OEM process survival.
- Backup encryption/authenticity signing is not introduced. The plan enforces structure, integrity, schema bounds, safe paths, and rollback, but a deliberately crafted valid SQLite database is still untrusted content. A later security phase may add authenticated/encrypted backups and deeper semantic database validation.
