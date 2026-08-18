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
import 'backup/backup_importer.dart';

/// 数据备份与恢复
abstract final class DataBackupService {
  /// 当前 APP 版本（与 pubspec.yaml 一致）
  static const _appVersion = '0.1.0';

  /// 需要导出的 SharedPreferences key 列表
  static const _exportPrefKeys = BackupImporter.restorePreferenceKeys;

  // ==================== 导出 ====================

  /// 导出完整备份到 ZIP 文件，保存到 Downloads 公共目录。
  ///
  /// 返回保存的文件路径。导出完成后会自动弹出系统分享面板。
  static Future<String> exportAndShare() async {
    // 1. 获取数据库路径
    final dbDirPath = await getDatabasesPath();
    final dbPath = '$dbDirPath/${DatabaseHelper.dbFileName}';

    // 2. 在数据库打开状态下构建 manifest（需要查询表行数）
    final manifest = await _buildManifest();

    // 3. 收集 SharedPreferences 配置
    final prefs = await SharedPreferences.getInstance();
    final prefMap = <String, dynamic>{};
    for (final key in _exportPrefKeys) {
      final value = prefs.get(key);
      if (value != null) {
        prefMap[key] = value;
      }
    }

    // 4. 关闭数据库确保数据全部刷盘。无论后续保存或分享是否失败，
    // 都必须恢复应用单例连接。
    await DatabaseHelper.close();
    try {
      // 5. 创建 ZIP 归档
      final archive = Archive();

      final manifestBytes = utf8.encode(jsonEncode(manifest));
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception('数据库文件不存在: $dbPath');
      }
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));

      final prefBytes = utf8.encode(jsonEncode(prefMap));
      archive.addFile(
        ArchiveFile('preferences.json', prefBytes.length, prefBytes),
      );

      final zipBytes = ZipEncoder().encode(archive);
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'taworld_backup_$timestamp';
      final savedPath = await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(zipBytes),
        ext: 'zip',
        mimeType: MimeType.zip,
      );

      await _recordBackupTime();
      if (savedPath.isNotEmpty) {
        await Share.shareXFiles([XFile(savedPath)], text: 'TaWorld 数据备份文件');
      }
      return savedPath;
    } finally {
      await DatabaseHelper.forceReopen();
    }
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

    return BackupArchiveCodec.decode(await file.readAsBytes()).info;
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

    final databasePath = await DatabaseHelper.getDatabasePath();
    final temporaryRoot = await getTemporaryDirectory();
    final preferences = await SharedPreferences.getInstance();
    await const BackupImporter().importBytes(
      await file.readAsBytes(),
      BackupImportDependencies(
        databasePath: databasePath,
        temporaryRoot: temporaryRoot,
        preferences: preferences,
        databaseFactory: databaseFactory,
        closeDatabase: DatabaseHelper.close,
        reopenDatabase: () async {
          await DatabaseHelper.forceReopen();
          return DatabaseHelper.database;
        },
      ),
    );
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
  static Future<Map<String, dynamic>> _buildManifest() async {
    final db = await DatabaseHelper.database;
    final tables = [
      'users',
      'partners',
      'reminder_configs',
      'reminder_logs',
      'achievements',
      'user_achievements',
      'chat_history',
      'ai_pending_messages',
      'ai_wiki_facts',
      'ai_conversation_summaries',
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
      'schema_version': DatabaseHelper.schemaVersion,
      'app_version': _appVersion,
      'created_at': DateTime.now().toIso8601String(),
      'tables': tables,
      'row_counts': rowCounts,
    };
  }

  /// 记录备份时间
  static Future<void> _recordBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'last_backup_time',
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
