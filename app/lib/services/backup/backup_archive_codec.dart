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
  final int missingAssetCount;

  const BackupInfo({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.rowCounts,
    this.missingAssetCount = 0,
  });

  /// Formats the metadata as a human-readable summary.
  String get summary {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(createdAt);
    final totalEntries = rowCounts.values.fold(0, (a, b) => a + b);
    return 'v$appVersion · schema v$schemaVersion · $dateStr\n共 $totalEntries 条数据记录'
        '${missingAssetCount == 0 ? '' : '\n原设备已有 $missingAssetCount 张图片缺失，备份中未包含这些图片'}';
  }
}

/// A backup archive whose structure, metadata, database, and preferences were
/// all validated before any import code can consume it.
class ValidatedBackupArchive {
  final BackupInfo info;
  final Uint8List databaseBytes;
  final Map<String, Object?> preferences;
  final Map<String, Uint8List> attachments;
  final Map<String, String> assetPaths;

  ValidatedBackupArchive({
    required this.info,
    required this.databaseBytes,
    required Map<String, Object?> preferences,
    Map<String, Uint8List> attachments = const {},
    this.assetPaths = const {},
  }) : preferences = Map.unmodifiable(preferences),
       attachments = Map.unmodifiable({
         for (final entry in attachments.entries)
           entry.key: Uint8List.fromList(entry.value),
       });
}

/// Thrown when a backup archive is malformed or violates the archive format.
class BackupFormatException implements Exception {
  final String message;

  const BackupFormatException(this.message);

  @override
  String toString() => 'BackupFormatException: $message';
}

class _ZipEntry {
  final String name;
  final Uint8List nameBytes;
  final int flags;
  final int compressionMethod;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  const _ZipEntry({
    required this.name,
    required this.nameBytes,
    required this.flags,
    required this.compressionMethod,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });
}

class _LocalZipEntry {
  final _ZipEntry entry;
  final int dataStart;
  final int dataEnd;

  const _LocalZipEntry({
    required this.entry,
    required this.dataStart,
    required this.dataEnd,
  });
}

class _ZipDirectory {
  final int centralOffset;
  final Map<String, _ZipEntry> entries;

  const _ZipDirectory({required this.centralOffset, required this.entries});
}

/// Output buffer that refuses to retain more than the entry's declared limit.
///
/// archive's pure-Dart [Inflate] catches output exceptions internally, so the
/// [exceeded] flag is checked after inflation as the authoritative signal.
class _BoundedOutputStream extends OutputStream {
  final int limit;
  Uint8List _buffer;
  @override
  int length = 0;
  bool exceeded = false;

  _BoundedOutputStream(this.limit)
    : _buffer = Uint8List(limit < 0x8000 ? limit : 0x8000),
      super(byteOrder: ByteOrder.littleEndian);

  void _requireCapacity(int additional) {
    if (additional < 0 || additional > limit - length) {
      exceeded = true;
      throw ArchiveException('decompressed output exceeds limit');
    }
    final required = length + additional;
    if (required <= _buffer.length) return;

    var nextLength = _buffer.isEmpty ? 1 : _buffer.length;
    while (nextLength < required) {
      final doubled = nextLength * 2;
      nextLength = doubled > limit ? limit : doubled;
    }
    _buffer = Uint8List(nextLength)..setRange(0, length, _buffer);
  }

  @override
  void clear() {
    length = 0;
    exceeded = false;
  }

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _requireCapacity(1);
    _buffer[length++] = value;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _requireCapacity(count);
    _buffer.setRange(this.length, this.length + count, bytes);
    this.length += count;
  }

  @override
  void writeStream(InputStream stream) {
    _requireCapacity(stream.length);
    if (stream is InputMemoryStream && stream.buffer != null) {
      _buffer.setRange(
        length,
        length + stream.length,
        stream.buffer!,
        stream.position,
      );
    } else {
      _buffer.setRange(length, length + stream.length, stream.toUint8List());
    }
    length += stream.length;
  }

  @override
  Uint8List subset(int start, [int? end]) {
    if (start < 0) start = length + start;
    end ??= length;
    if (end < 0) end = length + end;
    if (start < 0 || end < start || end > length) {
      throw RangeError.range(start, 0, length, 'start');
    }
    return Uint8List.view(
      _buffer.buffer,
      _buffer.offsetInBytes + start,
      end - start,
    );
  }

  @override
  Uint8List getBytes() {
    return Uint8List.view(_buffer.buffer, _buffer.offsetInBytes, length);
  }
}

/// Whitelist-only, in-memory backup archive decoder.
abstract final class BackupArchiveCodec {
  static const int maxArchiveBytes = 128 * 1024 * 1024;
  static const int maxDatabaseBytes = 256 * 1024 * 1024;
  static const int maxMetadataBytes = 1024 * 1024;
  static const int maxAttachmentBytes = 32 * 1024 * 1024;
  static const int maxTotalUncompressedBytes = 192 * 1024 * 1024;
  static const int maxAttachmentCount = 256;

  static const _manifestName = 'manifest.json';
  static const _databaseName = 'database.db';
  static const _preferencesName = 'preferences.json';
  static const _allowedNames = {_manifestName, _databaseName, _preferencesName};
  static final _attachmentName = RegExp(
    r'^attachments/([A-Za-z0-9_-]{1,120}\.(?:jpe?g|png|gif|webp))$',
    caseSensitive: false,
  );

  static const _eocdSignature = 0x06054b50;
  static const _centralSignature = 0x02014b50;
  static const _localSignature = 0x04034b50;
  static const _eocdLength = 22;
  static const _maxZipCommentLength = 0xffff;
  static const _zip64Uint16 = 0xffff;
  static const _zip64Uint32 = 0xffffffff;

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
    final directory = _readDirectory(bytes);
    final entries = directory.entries;

    final manifestEntry = entries[_manifestName];
    if (manifestEntry == null) {
      throw const BackupFormatException('缺少 manifest.json');
    }
    final databaseEntry = entries[_databaseName];
    if (databaseEntry == null) {
      throw const BackupFormatException('缺少 database.db');
    }

    // All local records are checked before any compressed content is read.
    final localEntries = _readLocalEntries(bytes, directory);

    // Parse metadata before obtaining database bytes. In particular, schema
    // compatibility is decided before any database lifecycle operation can be
    // introduced by a caller.
    final info = _parseManifest(
      _readEntry(bytes, localEntries[_manifestName]!),
    );
    final databaseBytes = _readEntry(bytes, localEntries[_databaseName]!);
    if (databaseBytes.isEmpty) {
      throw const BackupFormatException('database.db 不能为空');
    }

    final preferencesEntry = localEntries[_preferencesName];
    final manifest = _parseJsonObject(
      _readEntry(bytes, localEntries[_manifestName]!),
      _manifestName,
    );
    final assetPaths = <String, String>{};
    final rawPaths = manifest['asset_paths'];
    if (rawPaths != null) {
      if (rawPaths is! Map) throw const BackupFormatException('资源路径索引无效');
      for (final entry in rawPaths.entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            !_attachmentName.hasMatch('attachments/${entry.value}') ||
            !localEntries.containsKey('attachments/${entry.value}')) {
          throw const BackupFormatException('资源路径索引无效');
        }
        assetPaths[entry.key as String] = entry.value as String;
      }
    }
    final preferences = preferencesEntry == null
        ? <String, Object?>{}
        : _parsePreferences(_readEntry(bytes, preferencesEntry));
    final attachments = <String, Uint8List>{};
    for (final entry in localEntries.entries) {
      final match = _attachmentName.firstMatch(entry.key);
      if (match == null) continue;
      attachments[match.group(1)!] = _readEntry(bytes, entry.value);
    }

    return ValidatedBackupArchive(
      info: info,
      databaseBytes: databaseBytes,
      preferences: preferences,
      attachments: attachments,
      assetPaths: assetPaths,
    );
  }

  static _ZipDirectory _readDirectory(Uint8List bytes) {
    final eocdOffset = _findEocd(bytes);
    _requireRange(bytes, eocdOffset, _eocdLength, 'ZIP 结束记录');

    final diskNumber = _readUint16(bytes, eocdOffset + 4);
    final centralDisk = _readUint16(bytes, eocdOffset + 6);
    final entriesOnDisk = _readUint16(bytes, eocdOffset + 8);
    final entryCount = _readUint16(bytes, eocdOffset + 10);
    final centralSize = _readUint32(bytes, eocdOffset + 12);
    final centralOffset = _readUint32(bytes, eocdOffset + 16);

    if (diskNumber != 0 || centralDisk != 0 || entriesOnDisk != entryCount) {
      throw const BackupFormatException('不支持多卷 ZIP 归档');
    }
    if (entriesOnDisk == _zip64Uint16 ||
        entryCount == _zip64Uint16 ||
        centralSize == _zip64Uint32 ||
        centralOffset == _zip64Uint32) {
      throw const BackupFormatException('不支持 ZIP64 备份归档');
    }
    if (entryCount < 1 ||
        entryCount > _allowedNames.length + maxAttachmentCount) {
      throw const BackupFormatException('ZIP 条目数量无效');
    }
    _requireRange(bytes, centralOffset, centralSize, 'ZIP 中央目录');
    final centralEnd = centralOffset + centralSize;
    if (centralEnd != eocdOffset) {
      throw const BackupFormatException('ZIP 中央目录范围不一致');
    }

    final entries = <String, _ZipEntry>{};
    final localOffsets = <int>{};
    var totalUncompressedSize = 0;
    var offset = centralOffset;
    for (var index = 0; index < entryCount; index++) {
      _requireRange(bytes, offset, 46, 'ZIP 中央目录条目');
      if (_readUint32(bytes, offset) != _centralSignature) {
        throw const BackupFormatException('ZIP 中央目录签名无效');
      }

      final flags = _readUint16(bytes, offset + 8);
      final method = _readUint16(bytes, offset + 10);
      final crc32 = _readUint32(bytes, offset + 16);
      final compressedSize = _readUint32(bytes, offset + 20);
      final uncompressedSize = _readUint32(bytes, offset + 24);
      final nameLength = _readUint16(bytes, offset + 28);
      final extraLength = _readUint16(bytes, offset + 30);
      final commentLength = _readUint16(bytes, offset + 32);
      final diskStart = _readUint16(bytes, offset + 34);
      final externalAttributes = _readUint32(bytes, offset + 38);
      final localOffset = _readUint32(bytes, offset + 42);
      final recordLength = 46 + nameLength + extraLength + commentLength;
      _requireRange(bytes, offset, recordLength, 'ZIP 中央目录条目');
      if (offset + recordLength > centralEnd) {
        throw const BackupFormatException('ZIP 中央目录条目越界');
      }

      if (compressedSize == _zip64Uint32 ||
          uncompressedSize == _zip64Uint32 ||
          localOffset == _zip64Uint32 ||
          diskStart == _zip64Uint16) {
        throw const BackupFormatException('不支持 ZIP64 备份条目');
      }
      if (diskStart != 0) {
        throw const BackupFormatException('不支持跨卷 ZIP 条目');
      }

      final nameBytes = Uint8List.fromList(
        bytes.sublist(offset + 46, offset + 46 + nameLength),
      );
      final String name;
      try {
        name = utf8.decode(nameBytes, allowMalformed: false);
      } catch (_) {
        throw const BackupFormatException('ZIP 条目名称不是有效 UTF-8');
      }
      _validateEntryName(name);
      _validateFlagsAndMethod(name, flags, method);
      _validateAttributes(name, externalAttributes);
      _validateDeclaredSize(name, compressedSize, uncompressedSize);
      totalUncompressedSize += uncompressedSize;
      if (totalUncompressedSize > maxTotalUncompressedBytes) {
        throw const BackupFormatException('备份解压后超过总大小限制');
      }

      if (entries.containsKey(name)) {
        throw BackupFormatException('归档条目重复: $name');
      }
      if (!localOffsets.add(localOffset)) {
        throw const BackupFormatException('多个条目引用同一本地记录');
      }

      entries[name] = _ZipEntry(
        name: name,
        nameBytes: nameBytes,
        flags: flags,
        compressionMethod: method,
        crc32: crc32,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localOffset,
      );
      offset += recordLength;
    }

    if (offset != centralEnd) {
      throw const BackupFormatException('ZIP 中央目录包含未解析数据');
    }
    return _ZipDirectory(centralOffset: centralOffset, entries: entries);
  }

  static Map<String, _LocalZipEntry> _readLocalEntries(
    Uint8List bytes,
    _ZipDirectory directory,
  ) {
    final localEntries = <String, _LocalZipEntry>{};
    final ordered = directory.entries.values.toList()
      ..sort((a, b) => a.localHeaderOffset.compareTo(b.localHeaderOffset));

    var expectedOffset = 0;
    for (final entry in ordered) {
      final offset = entry.localHeaderOffset;
      if (offset != expectedOffset) {
        throw const BackupFormatException('ZIP 本地记录范围不连续');
      }
      _requireRange(bytes, offset, 30, 'ZIP 本地文件头');
      if (_readUint32(bytes, offset) != _localSignature) {
        throw BackupFormatException('ZIP 本地文件头无效: ${entry.name}');
      }

      final flags = _readUint16(bytes, offset + 6);
      final method = _readUint16(bytes, offset + 8);
      final crc32 = _readUint32(bytes, offset + 14);
      final compressedSize = _readUint32(bytes, offset + 18);
      final uncompressedSize = _readUint32(bytes, offset + 22);
      final nameLength = _readUint16(bytes, offset + 26);
      final extraLength = _readUint16(bytes, offset + 28);
      final headerLength = 30 + nameLength + extraLength;
      _requireRange(bytes, offset, headerLength, 'ZIP 本地文件头');

      final localNameBytes = bytes.sublist(
        offset + 30,
        offset + 30 + nameLength,
      );
      if (!_bytesEqual(localNameBytes, entry.nameBytes) ||
          flags != entry.flags ||
          method != entry.compressionMethod ||
          crc32 != entry.crc32 ||
          compressedSize != entry.compressedSize ||
          uncompressedSize != entry.uncompressedSize) {
        throw BackupFormatException('ZIP 中央目录与本地记录不一致: ${entry.name}');
      }

      final dataStart = offset + headerLength;
      _requireRange(bytes, dataStart, entry.compressedSize, 'ZIP 压缩数据');
      final dataEnd = dataStart + entry.compressedSize;
      if (dataEnd > directory.centralOffset) {
        throw BackupFormatException('ZIP 压缩数据越界: ${entry.name}');
      }
      expectedOffset = dataEnd;
      localEntries[entry.name] = _LocalZipEntry(
        entry: entry,
        dataStart: dataStart,
        dataEnd: dataEnd,
      );
    }

    if (expectedOffset != directory.centralOffset) {
      throw const BackupFormatException('ZIP 本地记录与中央目录之间包含隐藏数据');
    }
    return localEntries;
  }

  static void _validateEntryName(String name) {
    if (_allowedNames.contains(name) || _attachmentName.hasMatch(name)) return;
    if (name.isEmpty ||
        name.contains('\\') ||
        name.contains('..') ||
        name.startsWith('/') ||
        name.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        name.split('/').length > 2) {
      throw BackupFormatException('归档条目名称包含非法路径: $name');
    }
    throw BackupFormatException('不允许的归档条目: $name');
  }

  static void _validateFlagsAndMethod(String name, int flags, int method) {
    if ((flags & 0x0001) != 0 || (flags & 0x0040) != 0) {
      throw BackupFormatException('不支持加密 ZIP 条目: $name');
    }
    if ((flags & 0x0008) != 0) {
      throw BackupFormatException('不支持 data descriptor ZIP 条目: $name');
    }
    if (method != 0 && method != 8) {
      throw BackupFormatException('不支持的 ZIP 压缩方法: $name');
    }
    final supportedFlags = method == 8 ? 0x0806 : 0x0800;
    if ((flags & ~supportedFlags) != 0) {
      throw BackupFormatException('ZIP 条目标志不受支持: $name');
    }
  }

  static void _validateAttributes(String name, int externalAttributes) {
    final unixMode = externalAttributes >> 16;
    final fileType = unixMode & 0xf000;
    final dosDirectory = (externalAttributes & 0x10) != 0;
    if (fileType == 0x4000 || fileType == 0xa000 || dosDirectory) {
      throw BackupFormatException('不允许目录或链接条目: $name');
    }
  }

  static void _validateDeclaredSize(
    String name,
    int compressedSize,
    int uncompressedSize,
  ) {
    if (compressedSize < 0 || uncompressedSize < 0) {
      throw BackupFormatException('归档条目大小无效: $name');
    }
    if (name == _databaseName && uncompressedSize > maxDatabaseBytes) {
      throw const BackupFormatException('database.db 超过大小限制');
    }
    if ((name == _manifestName || name == _preferencesName) &&
        uncompressedSize > maxMetadataBytes) {
      throw BackupFormatException('$name 超过大小限制');
    }
    if (_attachmentName.hasMatch(name) &&
        uncompressedSize > maxAttachmentBytes) {
      throw BackupFormatException('$name 超过大小限制');
    }
    if (compressedSize > maxArchiveBytes) {
      throw BackupFormatException('$name 压缩数据超过大小限制');
    }
    if (!_allowedNames.contains(name) && !_attachmentName.hasMatch(name)) {
      throw BackupFormatException('不允许的归档条目: $name');
    }
  }

  static Uint8List _readEntry(Uint8List archiveBytes, _LocalZipEntry local) {
    final entry = local.entry;
    final compressed = Uint8List.sublistView(
      archiveBytes,
      local.dataStart,
      local.dataEnd,
    );
    final Uint8List output;
    if (entry.compressionMethod == 0) {
      if (entry.compressedSize != entry.uncompressedSize) {
        throw BackupFormatException('stored ZIP 条目大小不一致: ${entry.name}');
      }
      output = Uint8List.fromList(compressed);
    } else {
      final bounded = _BoundedOutputStream(entry.uncompressedSize);
      Inflate(compressed, output: bounded);
      if (bounded.exceeded) {
        throw BackupFormatException('归档条目解压后超过声明大小: ${entry.name}');
      }
      output = Uint8List.fromList(bounded.getBytes());
    }

    if (output.length != entry.uncompressedSize) {
      throw BackupFormatException('归档条目大小与声明不一致: ${entry.name}');
    }
    if (getCrc32(output) != entry.crc32) {
      throw BackupFormatException('归档条目校验失败: ${entry.name}');
    }
    return output;
  }

  static int _findEocd(Uint8List bytes) {
    if (bytes.length < _eocdLength) {
      throw const BackupFormatException('ZIP 归档缺少结束记录');
    }
    final firstCandidate = bytes.length - _eocdLength;
    final earliestCandidate =
        bytes.length - _eocdLength - _maxZipCommentLength < 0
        ? 0
        : bytes.length - _eocdLength - _maxZipCommentLength;
    for (var offset = firstCandidate; offset >= earliestCandidate; offset--) {
      if (_readUint32(bytes, offset) != _eocdSignature) continue;
      final commentLength = _readUint16(bytes, offset + 20);
      if (offset + _eocdLength + commentLength == bytes.length) {
        return offset;
      }
    }
    throw const BackupFormatException('ZIP 归档缺少有效结束记录');
  }

  static void _requireRange(
    Uint8List bytes,
    int offset,
    int length,
    String label,
  ) {
    if (offset < 0 ||
        length < 0 ||
        offset > bytes.length ||
        length > bytes.length - offset) {
      throw BackupFormatException('$label 越界');
    }
  }

  static int _readUint16(Uint8List bytes, int offset) {
    _requireRange(bytes, offset, 2, 'ZIP uint16');
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _readUint32(Uint8List bytes, int offset) {
    _requireRange(bytes, offset, 4, 'ZIP uint32');
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static bool _bytesEqual(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
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
    final timestampParts = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
      r'(?:\.\d{1,6})?(?:Z|([+-])(\d{2}):(\d{2}))?$',
    ).firstMatch(createdAtValue);
    if (timestampParts == null) {
      throw const BackupFormatException('created_at 无效');
    }
    final inputYear = int.parse(timestampParts.group(1)!);
    final inputMonth = int.parse(timestampParts.group(2)!);
    final inputDay = int.parse(timestampParts.group(3)!);
    final inputHour = int.parse(timestampParts.group(4)!);
    final inputMinute = int.parse(timestampParts.group(5)!);
    final inputSecond = int.parse(timestampParts.group(6)!);
    final offsetHour = timestampParts.group(8) == null
        ? 0
        : int.parse(timestampParts.group(8)!);
    final offsetMinute = timestampParts.group(9) == null
        ? 0
        : int.parse(timestampParts.group(9)!);
    if (inputHour > 23 ||
        inputMinute > 59 ||
        inputSecond > 59 ||
        offsetHour > 23 ||
        offsetMinute > 59) {
      throw const BackupFormatException('created_at 无效');
    }
    final calendarDate = DateTime.utc(inputYear, inputMonth, inputDay);
    if (calendarDate.year != inputYear ||
        calendarDate.month != inputMonth ||
        calendarDate.day != inputDay) {
      throw const BackupFormatException('created_at 无效');
    }
    final DateTime createdAt;
    try {
      createdAt = DateTime.parse(createdAtValue);
    } catch (_) {
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
      missingAssetCount: (manifest['missing_assets'] as List?)?.length ?? 0,
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
