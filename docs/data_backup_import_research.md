# 数据持久化与导出导入调研报告

## 现状评估

### SQLite 数据库（v4，8 张表）

| 表名 | 内容 | 用户关键数据 |
|------|------|:----------:|
| user | 用户昵称、头像 | 是 |
| partners | 关心的人（昵称、城市、关系等） | 是 |
| reminder_configs | 提醒配置（类别、时间、启用状态） | 是 |
| reminder_logs | 提醒触发记录 | 否（可重新生成） |
| achievements | 成就解锁状态 | 是 |
| chat_history | AI 对话历史 | 是 |
| ai_wiki_facts | Wiki 记忆事实 | 是（核心） |
| ai_conversation_summaries | 对话摘要 | 是 |
| conversation_chunks | RAG 对话片段 | 否（可重新积累） |
| ai_pending_messages | AI 待发送主动消息 | 否（临时） |

### SharedPreferences（15 个 key）

| Key | 内容 | 导出策略 |
|-----|------|---------|
| `deepseek_api_key` | API Key | **排除**（敏感信息，导入后需重新输入） |
| `theme_mode` | 亮色/暗色/跟随系统 | 导出 |
| `palette_id` | 色彩主题 | 导出 |
| `push_enabled` | 推送开关 | 导出 |
| `ai_proactive_enabled` | AI 主动推送开关 | 导出 |
| `has_completed_onboarding` | 是否完成引导 | 导出 |
| `last_dream_time` | 上次 Dreaming 时间戳 | 导出 |
| `last_proactive_time` | 上次主动推送时间戳 | 导出 |
| `proactive_count_YYYYMMDD` | 当日主动推送计数 | 不导出（临时） |
| `cache_hit_tokens` / `cache_miss_tokens` | 缓存统计 | 不导出（临时） |
| `bg_alert_time_*` | 后台告警去重时间戳 | 不导出（临时） |

### 迁移机制现状

当前 `_onUpgrade` 已经是正确的逐版本递进模式：

```dart
if (oldVersion < 2) { /* 创建 ai_pending_messages */ }
if (oldVersion < 3) { /* 创建 ai_wiki_facts + ai_conversation_summaries + 索引 */ }
if (oldVersion < 4) { /* 创建 conversation_chunks + 索引 */ }
```

**结论：APP 原地升级（覆盖安装）时数据是安全的。** sqflite 的 `onUpgrade` 会按版本逐步执行迁移，SQLite 文件在覆盖安装时完整保留。

### 数据丢失的风险场景

| 场景 | SQLite | SharedPreferences | 风险 |
|------|:------:|:-----------------:|:----:|
| 覆盖安装（应用商店/侧载 APK） | 保留 | 保留 | 低 |
| 卸载后重装 | **丢失** | **丢失** | **高** |
| 清除应用数据 | **丢失** | **丢失** | **高** |
| 换设备 | **丢失** | **丢失** | **高** |
| 恢复出厂设置 | **丢失** | **丢失** | **高** |

---

## 需求一：APP 升级数据安全

### 结论：当前已满足，只需维护

覆盖安装时 SQLite 数据库和 SharedPreferences 完整保留，`_onUpgrade` 已经是正确的逐版本迁移模式。**不需要额外开发**。

### 后续维护规则

每次修改数据库 schema 时：
1. `_dbVersion` +1
2. 在 `_onUpgrade` 末尾加一个 `if (oldVersion < 新版本号)` 块
3. 只用 `ALTER TABLE`（加列）和 `CREATE TABLE IF NOT EXISTS`（加表），不用 DROP
4. 在 `_onCreate` 中也加上新表/新列（新安装用户也需要）

### 建议增强：迁移前自动备份

在执行 `_onUpgrade` 之前，把当前数据库文件复制一份作为安全网：

```dart
static Future<void> _backupBeforeUpgrade(String dbPath) async {
  final file = File(dbPath);
  if (await file.exists()) {
    await file.copy('$dbPath.pre_upgrade_backup');
  }
}
```

在 `openDatabase` 之前调用。如果迁移失败，可以回滚。

---

## 需求二：一键导出/导入

### 推荐方案：ZIP 归档（SQLite 文件 + Preferences JSON）

#### 导出流程

```
1. 关闭数据库连接（确保数据全部刷盘）
2. 复制 SQLite 文件到临时目录
3. 导出 SharedPreferences 为 JSON
4. 用 archive 包将两者打成 ZIP
5. 用 file_saver 保存到 Downloads 公共目录（卸载 APP 后仍然存在）
6. 用 share_plus 弹出系统分享面板（用户可发到微信、邮件、网盘等）
```

#### 导入流程

```
1. 用 file_picker 让用户选择 ZIP 文件
2. 解压验证：检查是否包含有效的 SQLite 文件和 JSON
3. 弹出确认对话框：「导入将覆盖当前所有数据，确定吗？」
4. 备份当前数据库到 .pre_import_backup
5. 用导入的 SQLite 文件替换当前数据库
6. 导入 SharedPreferences（排除 API Key）
7. 重新打开数据库（onUpgrade 自动处理版本差异）
8. 重启 APP 或刷新所有页面
```

#### 备份文件格式

```
taworld_backup_20260612_1530.zip
├── manifest.json          ← 版本号、时间戳、校验和
├── database.db            ← SQLite 数据库文件
└── preferences.json       ← 非敏感配置项
```

`manifest.json` 示例：
```json
{
  "app_name": "TaWorld",
  "schema_version": 4,
  "app_version": "1.2.0",
  "created_at": "2026-06-12T15:30:00+08:00",
  "tables": ["user", "partners", "reminder_configs", ...],
  "row_counts": {
    "partners": 5,
    "ai_wiki_facts": 23,
    "chat_history": 150
  }
}
```

#### 版本兼容处理

导入时，如果备份的 schema_version 低于当前 APP 的 DB version：
- 把导入的 SQLite 文件放到数据库路径
- 用 `openDatabase(path, version: CURRENT_VERSION, onUpgrade: _onUpgrade)` 打开
- sqflite 自动检测版本差异并执行 `_onUpgrade`
- 无需额外编写版本转换逻辑

#### API Key 处理

API Key 存储在 SharedPreferences 中，属于敏感信息：
- **导出时排除**：不写入 `preferences.json`
- **导入后提示**：如果检测到 API Key 为空，在设置页显示提醒「请重新配置 AI API Key」

#### 需要新增的依赖

```yaml
dependencies:
  archive: ^4.0.4          # ZIP 压缩/解压
  file_saver: ^0.2.14      # 保存到公共 Downloads 目录
  file_picker: ^8.1.7      # 导入文件选择 + SAF 保存
  share_plus: ^10.1.4      # 系统分享面板
```

`path_provider` 和 `permission_handler` 已经在项目中。

#### UI 设计

在设置页的现有「账户」区块下方新增「数据管理」区块：

```
┌─────────────────────────────────────┐
│ 📦 数据管理                          │
├─────────────────────────────────────┤
│ 💾 导出备份                          │
│    导出所有数据为备份文件              │
│    上次备份: 2026-06-10 14:30       │
├─────────────────────────────────────┤
│ 📂 导入备份                          │
│    从备份文件恢复数据                 │
└─────────────────────────────────────┘
```

#### 核心代码结构

新建 `app/lib/services/data_backup_service.dart`：

```dart
abstract final class DataBackupService {
  /// 导出完整备份到 ZIP 文件
  static Future<File> exportBackup() async { ... }

  /// 从 ZIP 文件导入备份
  static Future<void> importBackup(File zipFile) async { ... }

  /// 验证备份文件是否有效
  static Future<BackupInfo> validateBackup(File zipFile) async { ... }

  /// 获取上次备份时间
  static Future<DateTime?> getLastBackupTime() async { ... }
}

class BackupInfo {
  final int schemaVersion;
  final String appVersion;
  final DateTime createdAt;
  final Map<String, int> rowCounts;
}
```

---

## 换设备迁移

### 推荐方案：导出 + 系统分享

用户操作流程：
1. 旧设备：设置 → 数据管理 → 导出备份 → 分享到微信/邮件/网盘
2. 新设备：安装 APP → 设置 → 数据管理 → 导入备份 → 选择文件 → 确认

这是最简单、最可靠、最符合离线优先理念的方案：
- 零额外依赖（不需要云服务、不需要登录）
- 100% 离线可用
- 用户完全掌控自己的数据
- 支持任何传输方式（微信、QQ、邮件、USB、蓝牙、网盘……）

### 可选增强：Google Drive 备份

如果后续想做云备份功能，可以通过 `google_sign_in` + `googleapis` 实现一键上传/下载 Google Drive。但这需要联网，与离线优先理念有冲突，建议作为可选项而非核心功能。

---

## 实施建议

| 优先级 | 任务 | 复杂度 | 涉及文件 |
|:-----:|------|:-----:|---------|
| P0 | 新建 `DataBackupService`（导出 + 导入 + 验证） | 中 | 新文件 + `database_helper.dart` |
| P0 | 设置页添加数据管理 UI | 低 | `settings_screen.dart` |
| P0 | 添加依赖（archive, file_saver, file_picker, share_plus） | 低 | `pubspec.yaml` |
| P1 | 迁移前自动备份 | 低 | `database_helper.dart` |
| P2 | Google Drive 云备份（可选） | 高 | 新文件 + pubspec |
