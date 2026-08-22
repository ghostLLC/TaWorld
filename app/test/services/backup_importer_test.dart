import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/backup/backup_importer.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late Directory temporaryRoot;
  late String livePath;
  late Directory attachmentsDirectory;
  late SharedPreferences preferences;
  late int closeCalls;
  late int reopenCalls;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('taworld_importer_test_');
    temporaryRoot = await Directory(p.join(root.path, 'temporary')).create();
    livePath = p.join(root.path, 'live.db');
    attachmentsDirectory = Directory(p.join(root.path, 'chat_images'));
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'palette_id': 'old',
      'push_enabled': false,
      'cache_hit_tokens': 41,
      'cache_miss_tokens': 42,
      'deepseek_api_key': 'local-secret',
      'untouched': 'keep',
    });
    preferences = await SharedPreferences.getInstance();
    closeCalls = 0;
    reopenCalls = 0;
    await DatabaseHelper.configureForTesting(
      factory: databaseFactoryFfi,
      path: livePath,
    );
    final db = await DatabaseHelper.database;
    await _insertUser(db, 'old-user');
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
    if (await root.exists()) await root.delete(recursive: true);
  });

  BackupImportDependencies dependencies({
    Future<void> Function(String stage)? afterStage,
    bool failFirstReopen = false,
    bool failRollbackClose = false,
  }) {
    var shouldFailReopen = failFirstReopen;
    return BackupImportDependencies(
      databasePath: livePath,
      temporaryRoot: temporaryRoot,
      preferences: preferences,
      databaseFactory: databaseFactoryFfi,
      closeDatabase: () async {
        closeCalls++;
        if (failRollbackClose && closeCalls > 1) {
          throw StateError('rollback close failed');
        }
        await DatabaseHelper.close();
      },
      reopenDatabase: () async {
        reopenCalls++;
        if (shouldFailReopen) {
          shouldFailReopen = false;
          throw StateError('migration failed');
        }
        await DatabaseHelper.forceReopen();
        return DatabaseHelper.database;
      },
      attachmentsDirectory: attachmentsDirectory,
      afterStage: afterStage,
    );
  }

  Future<void> expectNoTransientArtifacts() async {
    expect(await File('$livePath.incoming').exists(), isFalse);
    final children = await temporaryRoot.list().toList();
    expect(children, isEmpty);
  }

  test(
    'valid import migrates DB, whitelists prefs, and preserves API key',
    () async {
      final archive = await _backupBytes(
        root,
        userId: 'new-user',
        preferences: {
          'theme_mode': 'light',
          'palette_id': 'new',
          'push_enabled': true,
          'ai_proactive_enabled': true,
          'deepseek_api_key': 'malicious',
          'unknown': 'ignore',
          'last_backup_time': 123,
        },
      );

      await const BackupImporter().importBytes(archive, dependencies());

      final db = await DatabaseHelper.database;
      expect(await _userIds(db), ['new-user']);
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        DatabaseHelper.schemaVersion,
      );
      expect(preferences.getString('theme_mode'), 'light');
      expect(preferences.getString('palette_id'), 'new');
      expect(preferences.getBool('push_enabled'), isTrue);
      expect(preferences.getBool('ai_proactive_enabled'), isTrue);
      expect(preferences.getString('deepseek_api_key'), 'local-secret');
      expect(preferences.containsKey('unknown'), isFalse);
      expect(preferences.containsKey('last_backup_time'), isFalse);
      expect(preferences.getInt('cache_hit_tokens'), 0);
      expect(preferences.getInt('cache_miss_tokens'), 0);
      expect(await File('$livePath.pre_import_backup').exists(), isTrue);
      await expectNoTransientArtifacts();
    },
  );

  test(
    'valid import restores image bytes and rewrites portable paths',
    () async {
      const attachmentName = '0d90d534-4524-4d88-b11b-fb25cb72cc4d.png';
      final archive = await _backupBytes(
        root,
        userId: 'new-user',
        attachmentName: attachmentName,
        attachmentBytes: const [0x89, 0x50, 0x4e, 0x47, 1, 2, 3],
      );

      await const BackupImporter().importBytes(archive, dependencies());

      final db = await DatabaseHelper.database;
      final row = (await db.query('chat_attachments')).single;
      final restoredPath = row['local_path']! as String;
      expect(p.dirname(restoredPath), attachmentsDirectory.path);
      expect(await File(restoredPath).readAsBytes(), [
        0x89,
        0x50,
        0x4e,
        0x47,
        1,
        2,
        3,
      ]);
      expect(row['status'], 'local');
    },
  );

  test(
    'attachment restore failure removes new files and restores database',
    () async {
      const attachmentName = '0d90d534-4524-4d88-b11b-fb25cb72cc4d.png';
      final archive = await _backupBytes(
        root,
        userId: 'new-user',
        attachmentName: attachmentName,
        attachmentBytes: const [0x89, 0x50, 0x4e, 0x47],
      );

      await expectLater(
        const BackupImporter().importBytes(
          archive,
          dependencies(
            afterStage: (stage) async {
              if (stage == BackupImportStages.attachmentsRestored) {
                throw StateError('injected attachment failure');
              }
            },
          ),
        ),
        throwsA(isA<BackupImportException>()),
      );

      expect(await _userIds(await DatabaseHelper.database), ['old-user']);
      expect(
        await File(p.join(attachmentsDirectory.path, attachmentName)).exists(),
        isFalse,
      );
    },
  );

  test(
    'invalid archive fails before closing or changing the live DB',
    () async {
      final before = await File(livePath).readAsBytes();

      await expectLater(
        const BackupImporter().importBytes(
          Uint8List.fromList([1, 2, 3]),
          dependencies(),
        ),
        throwsA(anything),
      );

      expect(closeCalls, 0);
      expect(await File(livePath).readAsBytes(), before);
      expect(await _userIds(await DatabaseHelper.database), ['old-user']);
      await expectNoTransientArtifacts();
    },
  );

  test('non-SQLite staged database fails before closing the live DB', () async {
    final archive = _encodeBackup(
      Uint8List.fromList(utf8.encode('not sqlite')),
    );

    await expectLater(
      const BackupImporter().importBytes(archive, dependencies()),
      throwsA(anything),
    );

    expect(closeCalls, 0);
    expect(await _userIds(await DatabaseHelper.database), ['old-user']);
    await expectNoTransientArtifacts();
  });

  test('failure after replacement restores DB and all mutable prefs', () async {
    final archive = await _backupBytes(
      root,
      userId: 'new-user',
      preferences: {'theme_mode': 'light', 'palette_id': 'new'},
    );

    await expectLater(
      const BackupImporter().importBytes(
        archive,
        dependencies(
          afterStage: (stage) async {
            if (stage == BackupImportStages.databaseReplaced) {
              throw StateError('injected replacement failure');
            }
          },
        ),
      ),
      throwsA(
        isA<BackupImportException>().having(
          (e) => e.rollbackCause,
          'rollback',
          isNull,
        ),
      ),
    );

    expect(await _userIds(await DatabaseHelper.database), ['old-user']);
    expect(preferences.getString('theme_mode'), 'dark');
    expect(preferences.getString('palette_id'), 'old');
    expect(preferences.getInt('cache_hit_tokens'), 41);
    expect(preferences.getString('deepseek_api_key'), 'local-secret');
    await expectNoTransientArtifacts();
  });

  test(
    'migration/reopen failure restores and reopens the original DB',
    () async {
      final archive = await _backupBytes(root, userId: 'new-user');

      await expectLater(
        const BackupImporter().importBytes(
          archive,
          dependencies(failFirstReopen: true),
        ),
        throwsA(isA<BackupImportException>()),
      );

      expect(reopenCalls, 2);
      expect(await _userIds(await DatabaseHelper.database), ['old-user']);
      await expectNoTransientArtifacts();
    },
  );

  test(
    'failure after a preference write rolls back DB and preference absence',
    () async {
      final archive = await _backupBytes(
        root,
        userId: 'new-user',
        preferences: {'theme_mode': 'light', 'last_dream_time': 'today'},
      );

      await expectLater(
        const BackupImporter().importBytes(
          archive,
          dependencies(
            afterStage: (stage) async {
              if (stage ==
                  '${BackupImportStages.preferenceApplied}:last_dream_time') {
                throw StateError('preference write failed');
              }
            },
          ),
        ),
        throwsA(isA<BackupImportException>()),
      );

      expect(await _userIds(await DatabaseHelper.database), ['old-user']);
      expect(preferences.getString('theme_mode'), 'dark');
      expect(preferences.containsKey('last_dream_time'), isFalse);
      expect(preferences.getString('deepseek_api_key'), 'local-secret');
      await expectNoTransientArtifacts();
    },
  );

  test(
    'rollback failure is reported without losing the import cause',
    () async {
      final archive = await _backupBytes(root, userId: 'new-user');
      final importFailure = StateError('import failed');

      try {
        await const BackupImporter().importBytes(
          archive,
          dependencies(
            failRollbackClose: true,
            afterStage: (stage) async {
              if (stage == BackupImportStages.databaseReplaced) {
                throw importFailure;
              }
            },
          ),
        );
        fail('expected import failure');
      } on BackupImportException catch (e) {
        expect(e.cause, same(importFailure));
        expect(e.rollbackCause, isNotNull);
      }
    },
  );
}

Future<Uint8List> _backupBytes(
  Directory root, {
  required String userId,
  Map<String, Object?> preferences = const {},
  String? attachmentName,
  List<int> attachmentBytes = const [],
}) async {
  final path = p.join(
    root.path,
    'fixture_${DateTime.now().microsecondsSinceEpoch}.db',
  );
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE users (id TEXT PRIMARY KEY)');
        if (attachmentName != null) {
          await db.execute('''
            CREATE TABLE chat_attachments (
              id TEXT PRIMARY KEY,
              chat_message_id TEXT,
              local_path TEXT NOT NULL,
              mime_type TEXT NOT NULL,
              sha256 TEXT NOT NULL,
              width INTEGER,
              height INTEGER,
              model_summary TEXT,
              extracted_facts_json TEXT NOT NULL DEFAULT '[]',
              status TEXT NOT NULL DEFAULT 'local',
              created_at TEXT NOT NULL
            )
          ''');
        }
      },
    ),
  );
  await db.insert('users', {'id': userId});
  if (attachmentName != null) {
    await db.insert('chat_attachments', {
      'id': 'attachment-1',
      'chat_message_id': null,
      'local_path': 'C:/old-device/chat_images/$attachmentName',
      'mime_type': 'image/png',
      'sha256': 'fixture',
      'extracted_facts_json': '[]',
      'status': 'local',
      'created_at': '2026-08-22T12:00:00.000',
    });
  }
  await db.close();
  final bytes = await File(path).readAsBytes();
  await File(path).delete();
  return _encodeBackup(
    bytes,
    preferences: preferences,
    attachments: attachmentName == null
        ? const {}
        : {'attachments/$attachmentName': attachmentBytes},
  );
}

Uint8List _encodeBackup(
  Uint8List databaseBytes, {
  Map<String, Object?> preferences = const {},
  Map<String, List<int>> attachments = const {},
}) {
  final manifest = utf8.encode(
    jsonEncode({
      'app_name': 'TaWorld',
      'schema_version': 1,
      'app_version': '0.1.0',
      'created_at': '2026-08-18T12:00:00+08:00',
      'row_counts': {'users': 1},
    }),
  );
  final prefs = utf8.encode(jsonEncode(preferences));
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
    ..addFile(ArchiveFile('database.db', databaseBytes.length, databaseBytes))
    ..addFile(ArchiveFile('preferences.json', prefs.length, prefs));
  for (final attachment in attachments.entries) {
    archive.addFile(
      ArchiveFile(attachment.key, attachment.value.length, attachment.value),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<void> _insertUser(Database db, String id) async {
  await db.insert('users', {
    'id': id,
    'nickname': id,
    'created_at': '2026-08-18T00:00:00.000',
    'updated_at': '2026-08-18T00:00:00.000',
  });
}

Future<List<String>> _userIds(Database db) async {
  final rows = await db.query('users', columns: ['id'], orderBy: 'id');
  return rows.map((row) => row['id']! as String).toList();
}
