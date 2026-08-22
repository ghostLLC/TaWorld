import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/backup/backup_archive_codec.dart';

void main() {
  test('decodes a valid archive and copies its database bytes', () {
    final databaseBytes = Uint8List.fromList([1, 2, 3, 4]);
    final archiveBytes = _encodeArchive(
      databaseBytes: databaseBytes,
      preferences: {'theme_mode': 'system', 'push_enabled': true},
    );

    final decoded = BackupArchiveCodec.decode(archiveBytes);

    expect(decoded.info.schemaVersion, DatabaseHelper.schemaVersion);
    expect(decoded.info.appVersion, '0.1.0');
    expect(decoded.info.createdAt, DateTime.utc(2026, 8, 18, 8, 0));
    expect(decoded.info.rowCounts, {'users': 2, 'partners': 1});
    expect(decoded.databaseBytes, databaseBytes);
    expect(decoded.databaseBytes, isNot(same(databaseBytes)));
    expect(decoded.preferences, {'theme_mode': 'system', 'push_enabled': true});
  });

  test('returns an empty preference map when preferences are absent', () {
    final archiveBytes = _encodeArchive(includePreferences: false);

    expect(BackupArchiveCodec.decode(archiveBytes).preferences, isEmpty);
  });

  test('decodes validated image attachments without flattening paths', () {
    final archiveBytes = _encodeArchive(
      extraEntries: {
        'attachments/0d90d534-4524-4d88-b11b-fb25cb72cc4d.png': [
          0x89,
          0x50,
          0x4e,
          0x47,
        ],
      },
    );

    final decoded = BackupArchiveCodec.decode(archiveBytes);
    expect(decoded.attachments['0d90d534-4524-4d88-b11b-fb25cb72cc4d.png'], [
      0x89,
      0x50,
      0x4e,
      0x47,
    ]);
  });

  test('rejects unsafe or unsupported attachment names', () {
    for (final name in [
      'attachments/../evil.png',
      'attachments/subdir/evil.png',
      'attachments/evil.exe',
      'attachments/.png',
    ]) {
      expect(
        () => BackupArchiveCodec.decode(
          _encodeArchive(
            extraEntries: {
              name: [1],
            },
          ),
        ),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });

  test('decodes both stored and deflated TaWorld entries', () {
    final deflated = BackupArchiveCodec.decode(_encodeArchive());
    final stored = BackupArchiveCodec.decode(_encodeArchive(useStored: true));

    expect(deflated.databaseBytes, [1, 2, 3]);
    expect(stored.databaseBytes, [1, 2, 3]);
  });

  test('rejects an archive without a manifest', () {
    final archiveBytes = _encodeArchive(includeManifest: false);

    expect(
      () => BackupArchiveCodec.decode(archiveBytes),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects an archive without a database', () {
    final archiveBytes = _encodeArchive(includeDatabase: false);

    expect(
      () => BackupArchiveCodec.decode(archiveBytes),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects duplicate required and optional entries', () {
    for (final duplicateName in [
      'manifest.json',
      'database.db',
      'preferences.json',
    ]) {
      final archiveBytes = _encodeArchiveWithDuplicate(duplicateName);

      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
        reason: 'duplicate $duplicateName must be rejected',
      );
    }
  });

  test('rejects a true duplicate with a second local payload', () {
    final archiveBytes = _encodeArchiveWithDuplicate('database.db');

    expect(
      () => BackupArchiveCodec.decode(archiveBytes),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects encrypted entries and unsupported compression methods', () {
    final encrypted = _mutateCentralEntry(
      _encodeArchive(),
      'database.db',
      (bytes, offset) =>
          _writeUint16(bytes, offset + 8, _readUint16(bytes, offset + 8) | 0x1),
    );
    final unsupportedMethod = _mutateCentralEntry(
      _encodeArchive(),
      'database.db',
      (bytes, offset) => _writeUint16(bytes, offset + 10, 99),
    );

    for (final archiveBytes in [encrypted, unsupportedMethod]) {
      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });

  test('rejects symlink attributes and unsupported data descriptors', () {
    final symlink = _mutateCentralEntry(
      _encodeArchive(),
      'database.db',
      (bytes, offset) => _writeUint32(bytes, offset + 38, 0xa0000000),
    );
    final dataDescriptor = _mutateCentralEntry(
      _encodeArchive(),
      'database.db',
      (bytes, offset) =>
          _writeUint16(bytes, offset + 8, _readUint16(bytes, offset + 8) | 0x8),
    );

    for (final archiveBytes in [symlink, dataDescriptor]) {
      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });

  test('rejects central-directory count and padding inconsistencies', () {
    final countMismatch = _mutateArchive(
      _encodeArchive(),
      (bytes, eocd) =>
          _writeUint16(bytes, eocd + 10, _readUint16(bytes, eocd + 10) - 1),
    );
    final centralPadding = _insertBeforeEocd(_encodeArchive(), 0xa5);

    for (final archiveBytes in [countMismatch, centralPadding]) {
      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });

  test('rejects ZIP64 sentinel metadata', () {
    final zip64 = _mutateArchive(
      _encodeArchive(),
      (bytes, eocd) => _writeUint32(bytes, eocd + 12, 0xffffffff),
    );

    expect(
      () => BackupArchiveCodec.decode(zip64),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects central and local CRC disagreements', () {
    final mismatchedCrc = _mutateCentralEntry(
      _encodeArchive(),
      'database.db',
      (bytes, offset) =>
          _writeUint32(bytes, offset + 16, _readUint32(bytes, offset + 16) ^ 1),
    );

    expect(
      () => BackupArchiveCodec.decode(mismatchedCrc),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects a deflate stream that exceeds its declaration', () {
    final oversizedContent = _encodeArchive(
      databaseBytes: Uint8List.fromList(List<int>.filled(4096, 7)),
    );
    final malformedDeclaration = _mutateEntrySizes(
      oversizedContent,
      'database.db',
      1,
    );

    expect(
      () => BackupArchiveCodec.decode(malformedDeclaration),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects path-like and non-canonical entry names', () {
    for (final name in [
      '../evil.db',
      'subdir/database.db',
      r'C:\evil',
      r'\absolute',
      '/absolute',
      '..evil',
      'manifest.json.bak',
    ]) {
      final archiveBytes = _encodeArchive(
        extraEntries: {
          name: [1],
        },
      );

      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
        reason: 'entry $name must be rejected',
      );
    }
  });

  test('rejects directory entries and unknown files', () {
    final directoryArchive = Archive()
      ..addFile(ArchiveFile.directory('documents'))
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(_manifest())))
      ..addFile(ArchiveFile.bytes('database.db', [1]));
    final unknownArchive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(_manifest())))
      ..addFile(ArchiveFile.bytes('database.db', [1]))
      ..addFile(ArchiveFile.bytes('unknown.bin', [1]));

    for (final archive in [directoryArchive, unknownArchive]) {
      expect(
        () => BackupArchiveCodec.decode(_encode(archive)),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });

  test('rejects declared entry sizes over their limits', () {
    final oversizedDatabase = _encodeArchiveWithDeclaredSize(
      'database.db',
      BackupArchiveCodec.maxDatabaseBytes + 1,
    );
    final oversizedManifest = _encodeArchiveWithDeclaredSize(
      'manifest.json',
      BackupArchiveCodec.maxMetadataBytes + 1,
    );
    final oversizedPreferences = _encodeArchiveWithDeclaredSize(
      'preferences.json',
      BackupArchiveCodec.maxMetadataBytes + 1,
    );
    final oversizedAttachment = _encodeArchiveWithDeclaredSize(
      'attachments/0d90d534-4524-4d88-b11b-fb25cb72cc4d.png',
      BackupArchiveCodec.maxAttachmentBytes + 1,
    );

    for (final archiveBytes in [
      oversizedDatabase,
      oversizedManifest,
      oversizedPreferences,
      oversizedAttachment,
    ]) {
      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });

  test('rejects content whose size differs from its declaration', () {
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(_manifest())))
      ..addFile(ArchiveFile('database.db', 2, const [1, 2, 3]));

    expect(
      () => BackupArchiveCodec.decode(_encode(archive)),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects an archive larger than the compressed archive limit', () {
    final oversizedBytes = Uint8List(BackupArchiveCodec.maxArchiveBytes + 1);

    expect(
      () => BackupArchiveCodec.decode(oversizedBytes),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects invalid UTF-8 in the manifest', () {
    final archiveBytes = _encodeArchive(manifestBytes: [0xc3, 0x28]);

    expect(
      () => BackupArchiveCodec.decode(archiveBytes),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects invalid, non-object, and incomplete manifest JSON', () {
    for (final manifestBytes in [
      utf8.encode('{not json'),
      utf8.encode('[]'),
      utf8.encode(jsonEncode({..._manifest()}..remove('created_at'))),
    ]) {
      final archiveBytes = _encodeArchive(manifestBytes: manifestBytes);

      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
      );
    }
  });

  test('rejects invalid manifest metadata types and values', () {
    final cases = <Map<String, Object?>>[
      {..._manifest(), 'created_at': 'not-a-date'},
      {..._manifest(), 'created_at': '2026-02-30T08:00:00.000Z'},
      {..._manifest(), 'created_at': '2026-08-18T25:00:00'},
      {..._manifest(), 'created_at': '2026-08-18T23:59:60'},
      {..._manifest(), 'created_at': '2026-08-18T08:00:00+99:99'},
      {..._manifest(), 'created_at': 123},
      {..._manifest(), 'schema_version': '4'},
      {..._manifest(), 'schema_version': 1.5},
      {..._manifest(), 'schema_version': 0},
      {..._manifest(), 'schema_version': DatabaseHelper.schemaVersion + 1},
      {..._manifest(), 'app_name': 'OtherApp'},
      {..._manifest(), 'app_version': 42},
      {
        ..._manifest(),
        'row_counts': {'users': 1.5},
      },
      {
        ..._manifest(),
        'row_counts': {'users': '1'},
      },
      {..._manifest(), 'row_counts': []},
    ];

    for (final manifest in cases) {
      final archiveBytes = _encodeArchive(
        manifestBytes: utf8.encode(jsonEncode(manifest)),
      );

      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
        reason: 'manifest $manifest must be rejected',
      );
    }
  });

  test('rejects empty database bytes', () {
    final archiveBytes = _encodeArchive(databaseBytes: Uint8List(0));

    expect(
      () => BackupArchiveCodec.decode(archiveBytes),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('rejects malformed preference values', () {
    for (final value in [
      null,
      <String, Object?>{'nested': true},
      [1, 2],
    ]) {
      final archiveBytes = _encodeArchive(preferences: {'bad': value});

      expect(
        () => BackupArchiveCodec.decode(archiveBytes),
        throwsA(isA<BackupFormatException>()),
        reason: 'unsupported preference value $value must be rejected',
      );
    }
  });
}

Map<String, Object?> _manifest({int? schemaVersion}) => {
  'app_name': 'TaWorld',
  'schema_version': schemaVersion ?? DatabaseHelper.schemaVersion,
  'app_version': '0.1.0',
  'created_at': '2026-08-18T08:00:00.000Z',
  'row_counts': {'users': 2, 'partners': 1},
};

Uint8List _encodeArchive({
  bool includeManifest = true,
  bool includeDatabase = true,
  bool includePreferences = true,
  List<int>? manifestBytes,
  Uint8List? databaseBytes,
  Map<String, Object?>? preferences,
  bool useStored = false,
  Map<String, List<int>> extraEntries = const {},
}) {
  final archive = Archive();
  if (includeManifest) {
    final bytes = manifestBytes ?? utf8.encode(jsonEncode(_manifest()));
    archive.addFile(_archiveFile('manifest.json', bytes, useStored: useStored));
  }
  if (includeDatabase) {
    archive.addFile(
      _archiveFile(
        'database.db',
        databaseBytes ?? [1, 2, 3],
        useStored: useStored,
      ),
    );
  }
  if (includePreferences) {
    archive.addFile(
      _archiveFile(
        'preferences.json',
        utf8.encode(jsonEncode(preferences ?? {'theme_mode': 'system'})),
        useStored: useStored,
      ),
    );
  }
  for (final entry in extraEntries.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return _encode(archive);
}

ArchiveFile _archiveFile(
  String name,
  List<int> bytes, {
  bool useStored = false,
}) {
  final file = ArchiveFile.bytes(name, bytes);
  if (useStored) file.compression = CompressionType.none;
  return file;
}

Uint8List _encodeArchiveWithDeclaredSize(String name, int declaredSize) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('manifest.json', jsonEncode(_manifest())))
    ..addFile(ArchiveFile.bytes('database.db', [1, 2, 3]));
  if (name == 'manifest.json') {
    archive[0] = ArchiveFile(name, declaredSize, const <int>[]);
  } else if (name == 'database.db') {
    archive[1] = ArchiveFile(name, declaredSize, const <int>[]);
  } else {
    archive.addFile(ArchiveFile(name, declaredSize, const <int>[]));
  }
  return _encode(archive);
}

Uint8List _encodeArchiveWithDuplicate(String duplicateName) {
  // Archive.add replaces duplicate names, so build a valid archive first and
  // append a second central-directory/local-file pair in the helper below.
  final archive = Archive()
    ..addFile(ArchiveFile.string('manifest.json', jsonEncode(_manifest())))
    ..addFile(ArchiveFile.bytes('database.db', [1, 2, 3]))
    ..addFile(ArchiveFile.bytes('preferences.json', utf8.encode('{}')));
  return _duplicateZipEntry(_encode(archive), duplicateName);
}

Uint8List _encode(Archive archive) =>
    Uint8List.fromList(ZipEncoder().encode(archive));

Uint8List _duplicateZipEntry(Uint8List zip, String name) {
  // Copy the complete existing local record, including its real compressed
  // payload. This makes the duplicate a genuine second payload rather than a
  // central-directory-only duplicate.
  final eocd = _findSignature(zip, [0x50, 0x4b, 0x05, 0x06]);
  final centralOffset = _readUint32(zip, eocd + 16);
  final centralSize = _readUint32(zip, eocd + 12);
  final central = zip.sublist(centralOffset, centralOffset + centralSize);
  final recordOffset = _centralRecordOffsetForName(zip, name);
  final recordLength = _centralRecordLength(zip, recordOffset);
  final localOffset = _readUint32(zip, recordOffset + 42);
  final localLength =
      30 +
      _readUint16(zip, localOffset + 26) +
      _readUint16(zip, localOffset + 28) +
      _readUint32(zip, localOffset + 18);
  final duplicateLocal = zip.sublist(localOffset, localOffset + localLength);
  final duplicateCentral = zip.sublist(
    recordOffset,
    recordOffset + recordLength,
  );

  // Locate the existing central directory and EOCD. We insert the duplicate
  // local file immediately before the central directory, then duplicate the
  // selected central-directory record and update EOCD count/size/offset.
  final duplicateLocalOffset = centralOffset;
  _writeUint32(duplicateCentral, 42, duplicateLocalOffset);
  final rewrittenCentral = <int>[...central, ...duplicateCentral];
  final output = <int>[
    ...zip.sublist(0, centralOffset),
    ...duplicateLocal,
    ...rewrittenCentral,
    ...zip.sublist(eocd, zip.length),
  ];
  final newEocd = eocd + duplicateLocal.length + duplicateCentral.length;
  _writeUint16(output, newEocd + 8, _readUint16(output, newEocd + 8) + 1);
  _writeUint16(output, newEocd + 10, _readUint16(output, newEocd + 10) + 1);
  _writeUint32(output, newEocd + 12, rewrittenCentral.length);
  _writeUint32(output, newEocd + 16, centralOffset + duplicateLocal.length);
  return Uint8List.fromList(output);
}

Uint8List _mutateArchive(
  Uint8List zip,
  void Function(Uint8List bytes, int eocdOffset) mutate,
) {
  final bytes = Uint8List.fromList(zip);
  mutate(bytes, _findSignature(bytes, [0x50, 0x4b, 0x05, 0x06]));
  return bytes;
}

Uint8List _insertBeforeEocd(Uint8List zip, int value) {
  final eocd = _findSignature(zip, [0x50, 0x4b, 0x05, 0x06]);
  return Uint8List.fromList([
    ...zip.sublist(0, eocd),
    value,
    ...zip.sublist(eocd),
  ]);
}

Uint8List _mutateCentralEntry(
  Uint8List zip,
  String name,
  void Function(Uint8List bytes, int centralOffset) mutate,
) {
  final bytes = Uint8List.fromList(zip);
  mutate(bytes, _centralRecordOffsetForName(bytes, name));
  return bytes;
}

Uint8List _mutateEntrySizes(Uint8List zip, String name, int size) {
  final bytes = Uint8List.fromList(zip);
  final centralOffset = _centralRecordOffsetForName(bytes, name);
  final localOffset = _readUint32(bytes, centralOffset + 42);
  _writeUint32(bytes, centralOffset + 24, size);
  _writeUint32(bytes, localOffset + 22, size);
  return bytes;
}

int _centralRecordOffsetForName(List<int> zip, String name) {
  final eocd = _findSignature(zip, [0x50, 0x4b, 0x05, 0x06]);
  final centralOffset = _readUint32(zip, eocd + 16);
  final centralSize = _readUint32(zip, eocd + 12);
  final centralEnd = centralOffset + centralSize;
  var offset = centralOffset;
  final count = _readUint16(zip, eocd + 10);
  for (var index = 0; index < count; index++) {
    final recordLength = _centralRecordLength(zip, offset);
    final nameLength = _readUint16(zip, offset + 28);
    final candidate = utf8.decode(
      zip.sublist(offset + 46, offset + 46 + nameLength),
    );
    if (candidate == name) return offset;
    offset += recordLength;
  }
  if (offset > centralEnd) throw StateError('central directory overflow');
  throw StateError('central record not found');
}

int _centralRecordLength(List<int> zip, int offset) =>
    46 +
    _readUint16(zip, offset + 28) +
    _readUint16(zip, offset + 30) +
    _readUint16(zip, offset + 32);

int _findSignature(List<int> bytes, List<int> signature) {
  for (var i = bytes.length - signature.length; i >= 0; i--) {
    var matches = true;
    for (var j = 0; j < signature.length; j++) {
      if (bytes[i + j] != signature[j]) matches = false;
    }
    if (matches) return i;
  }
  throw StateError('signature not found');
}

int _readUint16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _readUint32(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void _writeUint16(List<int> bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _writeUint32(List<int> bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}
