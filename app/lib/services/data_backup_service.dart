/// TaWorld 数据备份与恢复服务
///
/// 支持将 SQLite 数据库 + SharedPreferences 配置导出为 ZIP 归档，
/// 以及从 ZIP 归档导入恢复数据。备份文件可通过系统分享面板发送到
/// 微信文件传输助手、QQ 我的电脑等渠道。
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'ai_service.dart';
import 'notification_service.dart';
import 'native_notification_bridge.dart';
import 'local/partner_service.dart';
import 'app_runtime.dart';
import 'theme_service.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local/database_helper.dart';
import 'backup/backup_archive_codec.dart';
import 'backup/backup_importer.dart';

/// 数据备份与恢复
abstract final class DataBackupService {
  /// 当前 APP 版本（与 pubspec.yaml 一致）
  static const _appVersion = '0.2.0';

  /// 需要导出的 SharedPreferences key 列表
  static const _exportPrefKeys = BackupImporter.restorePreferenceKeys;

  // ==================== 导出 ====================

  /// 导出完整备份到 ZIP 文件，保存到 Downloads 公共目录。
  ///
  /// 返回保存的文件路径。导出完成后会自动弹出系统分享面板。
  static Future<String> exportAndShare() async {
    final bytes = await createBackupBytes();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final savedPath = await FileSaver.instance.saveFile(
      name: 'taworld_backup_$stamp',
      bytes: bytes,
      ext: 'zip',
      mimeType: MimeType.zip,
    );
    await _recordBackupTime();
    if (savedPath.isNotEmpty) {
      await Share.shareXFiles([XFile(savedPath)], text: 'TaWorld 数据备份文件');
    }
    return savedPath;
  }

  /// Captures a consistent snapshot; the database is reopened before any system
  /// file picker or share sheet is shown.
  static Future<Uint8List> createBackupBytes() async {
    await AiService.stopAndWait();
    return DatabaseHelper.withMaintenance(() async {
      final manifest = await _buildManifest();
      final db = await DatabaseHelper.database;
      final assetRows = <String>[];
      for (final row in await db.query(
        'chat_attachments',
        columns: ['local_path'],
      )) {
        if (row['local_path'] is String) {
          assetRows.add(row['local_path'] as String);
        }
      }
      for (final table in ['partners', 'users']) {
        for (final row in await db.query(table, columns: ['avatar_path'])) {
          if (row['avatar_path'] is String) {
            assetRows.add(row['avatar_path'] as String);
          }
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final prefMap = {
        for (final key in _exportPrefKeys)
          if (prefs.get(key) != null) key: prefs.get(key),
      };
      final path = await DatabaseHelper.getDatabasePath();
      late Uint8List databaseBytes;
      await DatabaseHelper.close();
      try {
        databaseBytes = await File(path).readAsBytes();
      } finally {
        await DatabaseHelper.forceReopen();
      }
      final files = <String, Uint8List>{};
      final assetPaths = <String, String>{};
      var assetBytes = 0;
      final missing = <String>[];
      for (final path in assetRows.toSet()) {
        final file = File(path);
        if (!await file.exists()) {
          missing.add(p.basename(path));
          continue;
        }
        final ext = p.extension(path).toLowerCase();
        if (!const {'.jpg', '.jpeg', '.png', '.gif', '.webp'}.contains(ext)) {
          throw StateError('存在不支持的本地图片格式，请先更换图片后再备份');
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty ||
            bytes.length > BackupArchiveCodec.maxAttachmentBytes) {
          throw StateError('图片大小不符合备份要求，未生成不完整备份');
        }
        final name = '${sha256.convert(bytes)}$ext';
        assetPaths[path] = name;
        if (files.containsKey(name)) continue;
        assetBytes += bytes.length;
        if (files.length >= BackupArchiveCodec.maxAttachmentCount ||
            assetBytes + databaseBytes.length >
                BackupArchiveCodec.maxTotalUncompressedBytes -
                    2 * BackupArchiveCodec.maxMetadataBytes) {
          throw StateError('备份内容过多，请先整理不再需要的图片');
        }
        files[name] = bytes;
      }
      manifest.addAll({
        'asset_paths': assetPaths,
        'attachment_count': files.length,
        'attachment_bytes': assetBytes,
        'missing_assets': missing,
      });
      final archive = Archive();
      void add(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
      add('manifest.json', utf8.encode(jsonEncode(manifest)));
      add('database.db', databaseBytes);
      add('preferences.json', utf8.encode(jsonEncode(prefMap)));
      for (final entry in files.entries) {
        add('attachments/${entry.key}', entry.value);
      }
      final zipped = Uint8List.fromList(ZipEncoder().encode(archive));
      BackupArchiveCodec.decode(zipped);
      return zipped;
    });
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
  static Future<String?> importBackup(String zipPath) async {
    String? warning;
    final file = File(zipPath);
    if (!await file.exists()) {
      throw Exception('文件不存在');
    }

    final databasePath = await DatabaseHelper.getDatabasePath();
    final temporaryRoot = await getTemporaryDirectory();
    final preferences = await SharedPreferences.getInstance();
    final documents = await getApplicationDocumentsDirectory();
    await AiService.stopAndWait();
    await DatabaseHelper.withMaintenance(() async {
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
          attachmentsDirectory: Directory(
            p.join(documents.path, 'chat_images'),
          ),
        ),
      );
      // The import has committed. A device reconciliation error must never be
      // reported as a failed or rolled-back data import.
      try {
        await NotificationService.cancelAll();
        await NativeNotificationBridge.invoke<bool>('clearEvidence');
        final restored = await DatabaseHelper.database;
        await restored.transaction((tx) async {
          for (final table in [
            'runtime_locks',
            'scheduled_notifications',
            'notification_events',
            'background_runs',
          ]) {
            await tx.delete(table);
          }
        });
      } catch (_) {
        warning = '资料已导入，通知状态仍需重新检查，请打开“提醒自检”';
      }
    });
    PartnerService.notifyRefresh();
    try {
      await ThemeService.instance.init();
      await AppRuntime.resume(force: true);
    } catch (_) {
      warning ??= '资料已导入，部分设置尚未刷新，请重新打开 App 并检查提醒';
    }
    return warning;
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
      'reminder_occurrences',
      'chat_attachments',
      'schema_migrations',
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
