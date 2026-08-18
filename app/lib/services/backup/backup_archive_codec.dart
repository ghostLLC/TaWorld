/// Strict, memory-only decoding for TaWorld backup archives.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../../data/local/database_helper.dart';

/// Backup metadata that has passed the archive codec's validation rules.
class BackupInfo {
  final int schemaVersion;
  final String appVersion;
  final DateTime createdAt;
  final Map<String, int> rowCounts;

  const BackupInfo({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.rowCounts,
  });

  /// Formats the metadata as a human-readable summary.
  String get summary {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(createdAt);
    final totalEntries = rowCounts.values.fold(0, (a, b) => a + b);
    return 'v$appVersion · schema v$schemaVersion · $dateStr\n共 $totalEntries 条数据记录';
  }
}

/// A backup archive whose structure, metadata, database, and preferences were
/// all validated before any import code can consume it.
class ValidatedBackupArchive {
  final BackupInfo info;
  final Uint8List databaseBytes;
  final Map<String, Object?> preferences;

  ValidatedBackupArchive({
    required this.info,
    required this.databaseBytes,
    required Map<String, Object?> preferences,
  }) : preferences = Map.unmodifiable(preferences);
}

/// Thrown when a backup archive is malformed or violates the archive format.
class BackupFormatException implements Exception {
  final String message;

  const BackupFormatException(this.message);

  @override
  String toString() => 'BackupFormatException: $message';
}

/// Whitelist-only, in-memory backup archive decoder.
abstract final class BackupArchiveCodec {
  static const int maxArchiveBytes = 128 * 1024 * 1024;
  static const int maxDatabaseBytes = 256 * 1024 * 1024;
  static const int maxMetadataBytes = 1024 * 1024;

  static const _manifestName = 'manifest.json';
  static const _databaseName = 'database.db';
  static const _preferencesName = 'preferences.json';
  static const _allowedNames = {_manifestName, _databaseName, _preferencesName};

  /// Decodes and validates a backup archive without touching the filesystem.
  static ValidatedBackupArchive decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const BackupFormatException('备份归档为空');
    }
    if (bytes.length > maxArchiveBytes) {
      throw const BackupFormatException('备份归档超过大小限制');
    }

    try {
      return _decode(bytes);
    } on BackupFormatException {
      rethrow;
    } catch (error) {
      throw BackupFormatException('无法读取备份归档: $error');
    }
  }

  static ValidatedBackupArchive _decode(Uint8List bytes) {
    final decoder = ZipDecoder();

    // archive exposes ZIP integrity verification through this flag. The
    // installed implementation performs the CRC check when entry content is
    // read below, so both the API-level request and the explicit check are
    // retained here.
    final archive = decoder.decodeBytes(bytes, verify: true);
    final headers = decoder.directory.fileHeaders;
    final entries = <String, ZipFileHeader>{};

    // Validate every central-directory entry before reading any allowed
    // content. Archive itself deduplicates names, therefore the raw directory
    // headers are used for duplicate detection.
    for (final header in headers) {
      _validateEntry(header, archive, entries);
    }

    final manifestHeader = entries[_manifestName];
    if (manifestHeader == null) {
      throw const BackupFormatException('缺少 manifest.json');
    }
    final databaseHeader = entries[_databaseName];
    if (databaseHeader == null) {
      throw const BackupFormatException('缺少 database.db');
    }

    // Parse metadata before obtaining database bytes. In particular, schema
    // compatibility is decided before any database lifecycle operation can be
    // introduced by a caller.
    final info = _parseManifest(_readEntry(manifestHeader, _manifestName));
    final databaseBytes = _readEntry(databaseHeader, _databaseName);
    if (databaseBytes.isEmpty) {
      throw const BackupFormatException('database.db 不能为空');
    }

    final preferencesHeader = entries[_preferencesName];
    final preferences = preferencesHeader == null
        ? <String, Object?>{}
        : _parsePreferences(_readEntry(preferencesHeader, _preferencesName));

    return ValidatedBackupArchive(
      info: info,
      // _readEntry already copies the decompressed bytes out of the archive.
      databaseBytes: databaseBytes,
      preferences: preferences,
    );
  }

  static void _validateEntry(
    ZipFileHeader header,
    Archive archive,
    Map<String, ZipFileHeader> entries,
  ) {
    final name = header.filename;
    _validateEntryName(name);

    final file = header.file;
    if (file == null) {
      throw BackupFormatException('归档条目缺少本地文件头: $name');
    }
    if (file.filename != name) {
      throw BackupFormatException('归档条目名称不一致: $name');
    }

    final archiveEntry = archive.find(name);
    if (archiveEntry == null) {
      throw BackupFormatException('无法读取归档条目: $name');
    }
    if (!archiveEntry.isFile ||
        archiveEntry.isSymbolicLink ||
        _hasDirectoryOrSymlinkAttributes(header)) {
      throw BackupFormatException('不允许目录或链接条目: $name');
    }
    if (!entries.containsKey(name)) {
      entries[name] = header;
    } else {
      throw BackupFormatException('归档条目重复: $name');
    }

    final size = header.uncompressedSize;
    if (size < 0) {
      throw BackupFormatException('归档条目大小无效: $name');
    }
    if (name == _databaseName && size > maxDatabaseBytes) {
      throw const BackupFormatException('database.db 超过大小限制');
    }
    if ((name == _manifestName || name == _preferencesName) &&
        size > maxMetadataBytes) {
      throw BackupFormatException('$name 超过大小限制');
    }
  }

  static void _validateEntryName(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('..') ||
        name.startsWith('/') ||
        name.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      throw BackupFormatException('归档条目名称包含非法路径: $name');
    }
    if (!_allowedNames.contains(name)) {
      throw BackupFormatException('不允许的归档条目: $name');
    }
  }

  static bool _hasDirectoryOrSymlinkAttributes(ZipFileHeader header) {
    final unixMode = header.externalFileAttributes >> 16;
    final fileType = unixMode & 0xf000;
    final dosDirectory = (header.externalFileAttributes & 0x10) != 0;
    return fileType == 0x4000 || fileType == 0xa000 || dosDirectory;
  }

  static Uint8List _readEntry(ZipFileHeader header, String name) {
    final file = header.file;
    if (file == null) {
      throw BackupFormatException('归档条目不可读: $name');
    }

    final bytes = file.readBytes();
    if (bytes.length != header.uncompressedSize) {
      throw BackupFormatException('归档条目大小与声明不一致: $name');
    }
    if (!file.verifyCrc32()) {
      throw BackupFormatException('归档条目校验失败: $name');
    }
    return Uint8List.fromList(bytes);
  }

  static BackupInfo _parseManifest(Uint8List bytes) {
    final manifest = _parseJsonObject(bytes, 'manifest.json');

    final appName = manifest['app_name'];
    if (appName != 'TaWorld') {
      throw const BackupFormatException('不是 TaWorld 的备份文件');
    }

    final schemaVersion = manifest['schema_version'];
    if (schemaVersion is! int ||
        schemaVersion < 1 ||
        schemaVersion > DatabaseHelper.schemaVersion) {
      throw const BackupFormatException('schema_version 不受支持');
    }

    final appVersion = manifest['app_version'];
    if (appVersion is! String || appVersion.isEmpty) {
      throw const BackupFormatException('app_version 无效');
    }

    final createdAtValue = manifest['created_at'];
    if (createdAtValue is! String || createdAtValue.isEmpty) {
      throw const BackupFormatException('created_at 无效');
    }
    final DateTime createdAt;
    try {
      createdAt = DateTime.parse(createdAtValue);
    } catch (_) {
      throw const BackupFormatException('created_at 无效');
    }
    final dateParts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})')
        .firstMatch(createdAtValue);
    if (dateParts == null) {
      throw const BackupFormatException('created_at 无效');
    }
    final inputYear = int.parse(dateParts.group(1)!);
    final inputMonth = int.parse(dateParts.group(2)!);
    final inputDay = int.parse(dateParts.group(3)!);
    final calendarDate = DateTime.utc(inputYear, inputMonth, inputDay);
    if (calendarDate.year != inputYear ||
        calendarDate.month != inputMonth ||
        calendarDate.day != inputDay) {
      throw const BackupFormatException('created_at 无效');
    }

    final rowCountsValue = manifest['row_counts'];
    if (rowCountsValue is! Map) {
      throw const BackupFormatException('row_counts 无效');
    }
    final rowCounts = <String, int>{};
    for (final entry in rowCountsValue.entries) {
      if (entry.key is! String || entry.value is! int || entry.value < 0) {
        throw const BackupFormatException('row_counts 必须是非负整数');
      }
      rowCounts[entry.key as String] = entry.value as int;
    }

    return BackupInfo(
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      createdAt: createdAt,
      rowCounts: rowCounts,
    );
  }

  static Map<String, Object?> _parsePreferences(Uint8List bytes) {
    final object = _parseJsonObject(bytes, 'preferences.json');
    final preferences = <String, Object?>{};
    for (final entry in object.entries) {
      final value = entry.value;
      if (value is String || value is bool || value is int || value is double) {
        preferences[entry.key] = value;
      } else {
        throw BackupFormatException('preference ${entry.key} 包含不支持的值类型');
      }
    }
    return preferences;
  }

  static Map<String, Object?> _parseJsonObject(
    Uint8List bytes,
    String entryName,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw BackupFormatException('$entryName 不是有效的 UTF-8 JSON');
    }
    if (decoded is! Map) {
      throw BackupFormatException('$entryName 必须是 JSON 对象');
    }

    final object = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw BackupFormatException('$entryName 包含无效键');
      }
      object[entry.key as String] = entry.value;
    }
    return object;
  }
}
