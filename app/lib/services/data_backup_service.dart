/// TaWorld 数据备份与恢复服务
///
/// 支持将 SQLite 数据库 + SharedPreferences 配置导出为 ZIP 归档，
/// 以及从 ZIP 归档导入恢复数据。备份文件可通过系统分享面板发送到
/// 微信文件传输助手、QQ 我的电脑等渠道。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local/database_helper.dart';
import 'backup/backup_archive_codec.dart';

/// 数据备份与恢复
abstract final class DataBackupService {
  /// 当前数据库 schema 版本（必须与 DatabaseHelper._dbVersion 一致）
  static const _currentSchemaVersion = 4;

  /// 当前 APP 版本（与 pubspec.yaml 一致）
  static const _appVersion = '0.1.0';

  /// 需要导出的 SharedPreferences key 列表
  static const _exportPrefKeys = [
    'theme_mode',
    'palette_id',
    'push_enabled',
    'ai_proactive_enabled',
    'last_dream_time',
    'last_proactive_time',
  ];

  // ==================== 导出 ====================

  /// 导出完整备份到 ZIP 文件，保存到 Downloads 公共目录。
  ///
  /// 返回保存的文件路径。导出完成后会自动弹出系统分享面板。
  static Future<String> exportAndShare() async {
    // 1. 获取数据库路径
    final dbDirPath = await getDatabasesPath();
    final dbPath = '$dbDirPath/${DatabaseHelper.dbFileName}';

    // 2. 在数据库打开状态下构建 manifest（需要查询表行数）
    final manifest = await _buildManifest(dbPath);

    // 3. 收集 SharedPreferences 配置
    final prefs = await SharedPreferences.getInstance();
    final prefMap = <String, dynamic>{};
    for (final key in _exportPrefKeys) {
      final value = prefs.get(key);
      if (value != null) {
        prefMap[key] = value;
      }
    }

    // 4. 关闭数据库确保数据全部刷盘
    await DatabaseHelper.close();

    // 5. 创建 ZIP 归档
    final archive = Archive();

    // 5a. 添加 manifest.json
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    // 5b. 添加数据库文件
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('数据库文件不存在: $dbPath');
    }
    final dbBytes = await dbFile.readAsBytes();
    archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));

    // 5c. 添加 preferences.json
    final prefBytes = utf8.encode(jsonEncode(prefMap));
    archive.addFile(ArchiveFile('preferences.json', prefBytes.length, prefBytes));

    // 6. 压缩为 ZIP
    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    // 7. 保存到 Downloads 公共目录
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'taworld_backup_$timestamp';

    final savedPath = await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(zipBytes),
      ext: 'zip',
      mimeType: MimeType.zip,
    );

    // 8. 记录备份时间
    await _recordBackupTime();

    // 9. 弹出系统分享面板
    if (savedPath.isNotEmpty) {
      await Share.shareXFiles(
        [XFile(savedPath)],
        text: 'TaWorld 数据备份文件',
      );
    }

    return savedPath;
  }

  // ==================== 导入 ====================

  /// 让用户通过系统文件选择器选取备份文件。
  ///
  /// 使用 `FileType.any` 触发 ACTION_GET_CONTENT，
  /// 系统文件选择器的「最近」栏目会自动展示从微信、QQ 等应用接收的文件。
  ///
  /// 返回选中的文件路径，null 表示用户取消了选择。
  static Future<String?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    return result?.files.single.path;
  }

  /// 验证备份 ZIP 文件是否有效，返回元信息。
  static Future<BackupInfo> validateBackup(String zipPath) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      throw Exception('文件不存在');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 检查必须包含 manifest.json
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw Exception('无效的备份文件：缺少 manifest.json');
    }

    final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;

    // 检查是否 TaWorld 备份
    if (manifest['app_name'] != 'TaWorld') {
      throw Exception('不是 TaWorld 的备份文件');
    }

    // 检查是否包含数据库
    if (archive.findFile('database.db') == null) {
      throw Exception('无效的备份文件：缺少数据库');
    }

    return BackupInfo(
      schemaVersion: manifest['schema_version'] as int? ?? 0,
      appVersion: manifest['app_version'] as String? ?? 'unknown',
      createdAt: DateTime.tryParse(manifest['created_at'] as String? ?? '') ?? DateTime.now(),
      rowCounts: (manifest['row_counts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
    );
  }

  /// 从 ZIP 文件导入备份，覆盖当前所有数据。
  ///
  /// 导入前会自动备份当前数据到 `.pre_import_backup` 文件。
  /// 如果导入的数据库版本低于当前 APP 版本，sqflite 的 onUpgrade 会自动迁移。
  static Future<void> importBackup(String zipPath) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      throw Exception('文件不存在');
    }

    // 1. 关闭当前数据库
    await DatabaseHelper.close();

    try {
      // 2. 备份当前数据（安全网）
      await _backupCurrentData();

      // 3. 解压 ZIP 到临时目录
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/import_temp');
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      for (final entry in archive) {
        if (!entry.isFile) continue;
        final entryFile = File('${extractDir.path}/${entry.name}');
        await entryFile.writeAsBytes(entry.content as List<int>);
      }

      // 4. 替换数据库
      final importedDb = File('${extractDir.path}/database.db');
      if (await importedDb.exists()) {
        final dbDirPath = await getDatabasesPath();
        final dbPath = '$dbDirPath/${DatabaseHelper.dbFileName}';
        await importedDb.copy(dbPath);
      }

      // 5. 恢复 SharedPreferences（排除 API Key）
      final importedPrefs = File('${extractDir.path}/preferences.json');
      if (await importedPrefs.exists()) {
        final prefStr = await importedPrefs.readAsString();
        final prefMap = jsonDecode(prefStr) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();

        for (final entry in prefMap.entries) {
          final value = entry.value;
          if (value is String) {
            await prefs.setString(entry.key, value);
          } else if (value is bool) {
            await prefs.setBool(entry.key, value);
          } else if (value is int) {
            await prefs.setInt(entry.key, value);
          } else if (value is double) {
            await prefs.setDouble(entry.key, value);
          }
        }

        // 清除缓存统计（属于旧数据）
        await prefs.setInt('cache_hit_tokens', 0);
        await prefs.setInt('cache_miss_tokens', 0);
      }

      // 6. 清理临时文件
      await extractDir.delete(recursive: true);

      // 7. 重新打开数据库（如果版本较低，onUpgrade 自动迁移）
      await DatabaseHelper.forceReopen();
    } catch (e) {
      // 导入失败时尝试恢复数据库连接
      await DatabaseHelper.forceReopen();
      rethrow;
    }
  }

  /// 获取上次备份时间
  static Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('last_backup_time');
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  // ==================== 内部方法 ====================

  /// 构建 manifest.json 内容
  static Future<Map<String, dynamic>> _buildManifest(String dbPath) async {
    final db = await DatabaseHelper.database;
    final tables = [
      'users', 'partners', 'reminder_configs', 'reminder_logs',
      'achievements', 'user_achievements', 'chat_history',
      'ai_pending_messages', 'ai_wiki_facts', 'ai_conversation_summaries',
      'conversation_chunks',
    ];

    final rowCounts = <String, int>{};
    for (final table in tables) {
      try {
        final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $table');
        rowCounts[table] = result.first['cnt'] as int? ?? 0;
      } catch (_) {
        // 表可能不存在，跳过
      }
    }

    return {
      'app_name': 'TaWorld',
      'schema_version': _currentSchemaVersion,
      'app_version': _appVersion,
      'created_at': DateTime.now().toIso8601String(),
      'tables': tables,
      'row_counts': rowCounts,
    };
  }

  /// 备份当前数据库和配置到临时文件
  static Future<void> _backupCurrentData() async {
    final dbDirPath = await getDatabasesPath();
    final dbPath = '$dbDirPath/${DatabaseHelper.dbFileName}';
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.copy('$dbPath.pre_import_backup');
    }

    final prefs = await SharedPreferences.getInstance();
    final prefMap = <String, dynamic>{};
    for (final key in _exportPrefKeys) {
      final value = prefs.get(key);
      if (value != null) prefMap[key] = value;
    }
    // 也保存 API Key 到备份（不导出到 ZIP，但保留在本机备份中）
    final apiKey = prefs.getString('deepseek_api_key');
    if (apiKey != null) prefMap['deepseek_api_key'] = apiKey;

    final backupPrefsPath = '$dbDirPath/preferences.pre_import_backup.json';
    await File(backupPrefsPath).writeAsString(jsonEncode(prefMap));
  }

  /// 记录备份时间
  static Future<void> _recordBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_backup_time', DateTime.now().millisecondsSinceEpoch);
  }
}
