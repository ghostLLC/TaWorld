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

    for (final archiveBytes in [
      oversizedDatabase,
      oversizedManifest,
      oversizedPreferences,
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
  Map<String, List<int>> extraEntries = const {},
}) {
  final archive = Archive();
  if (includeManifest) {
    final bytes = manifestBytes ?? utf8.encode(jsonEncode(_manifest()));
    archive.addFile(ArchiveFile.bytes('manifest.json', bytes));
  }
  if (includeDatabase) {
    archive.addFile(
      ArchiveFile.bytes('database.db', databaseBytes ?? [1, 2, 3]),
    );
  }
  if (includePreferences) {
    archive.addFile(
      ArchiveFile.bytes(
        'preferences.json',
        utf8.encode(jsonEncode(preferences ?? {'theme_mode': 'system'})),
      ),
    );
  }
  for (final entry in extraEntries.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return _encode(archive);
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
  // This fixture is intentionally small and uses the standard ZIP layout
  // emitted by archive. The codec must inspect central-directory entries
  // rather than relying on Archive.find, which deduplicates by name.
  final decoder = ZipDecoder();
  decoder.decodeBytes(zip);
  final headers = decoder.directory.fileHeaders;
  final headerIndex = headers.indexWhere(
    (candidate) => candidate.filename == name,
  );
  final header = headers[headerIndex];
  final file = header.file!;
  final localName = utf8.encode(name);
  final content = file.getRawContent();
  final duplicateLocal = <int>[
    0x50,
    0x4b,
    0x03,
    0x04,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    file.crc32 & 0xff,
    (file.crc32 >> 8) & 0xff,
    (file.crc32 >> 16) & 0xff,
    (file.crc32 >> 24) & 0xff,
    content.length & 0xff,
    (content.length >> 8) & 0xff,
    (content.length >> 16) & 0xff,
    (content.length >> 24) & 0xff,
    file.uncompressedSize & 0xff,
    (file.uncompressedSize >> 8) & 0xff,
    (file.uncompressedSize >> 16) & 0xff,
    (file.uncompressedSize >> 24) & 0xff,
    localName.length & 0xff,
    (localName.length >> 8) & 0xff,
    0,
    0,
    ...localName,
    ...content,
  ];

  // Locate the existing central directory and EOCD. We insert the duplicate
  // local file immediately before the central directory, then duplicate the
  // selected central-directory record and update EOCD count/size/offset.
  final eocd = _findSignature(zip, [0x50, 0x4b, 0x05, 0x06]);
  final centralOffset = _readUint32(zip, eocd + 16);
  final centralSize = _readUint32(zip, eocd + 12);
  final central = zip.sublist(centralOffset, centralOffset + centralSize);
  final duplicateCentral = _centralRecordAt(central, headerIndex);
  final duplicateLocalOffset = centralOffset;
  final rewrittenCentral = <int>[...central, ...duplicateCentral];
  _writeUint32(duplicateCentral, 42, duplicateLocalOffset);
  final output = <int>[
    ...zip.sublist(0, centralOffset),
    ...duplicateLocal,
    ...rewrittenCentral,
    ...zip.sublist(eocd, zip.length),
  ];
  final newEocd = eocd + duplicateLocal.length;
  _writeUint16(output, newEocd + 8, _readUint16(output, newEocd + 8) + 1);
  _writeUint16(output, newEocd + 10, _readUint16(output, newEocd + 10) + 1);
  _writeUint32(output, newEocd + 12, rewrittenCentral.length);
  _writeUint32(output, newEocd + 16, centralOffset + duplicateLocal.length);
  return Uint8List.fromList(output);
}

List<int> _centralRecordAt(List<int> central, int targetIndex) {
  var offset = 0;
  for (var index = 0; index < targetIndex; index++) {
    if (offset + 46 > central.length) {
      throw StateError('central record not found');
    }
    final length =
        46 +
        _readUint16(central, offset + 28) +
        _readUint16(central, offset + 30) +
        _readUint16(central, offset + 32);
    offset += length;
  }
  if (offset + 46 > central.length) {
    throw StateError('central record not found');
  }
  final length =
      46 +
      _readUint16(central, offset + 28) +
      _readUint16(central, offset + 30) +
      _readUint16(central, offset + 32);
  if (offset + length > central.length) {
    throw StateError('central record not found');
  }
  return central.sublist(offset, offset + length);
}

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
