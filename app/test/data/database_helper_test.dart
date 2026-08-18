import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/data/models/achievement.dart';

import '../helpers/test_database.dart';

const _applicationTables = {
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
};

const _applicationIndexes = {
  'idx_reminder_configs_partner',
  'idx_reminder_logs_config',
  'idx_reminder_logs_partner',
  'idx_user_achievements_achievement',
  'idx_ai_wiki_facts_category',
  'idx_ai_wiki_facts_entity',
  'idx_conversation_chunks_date',
};

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

  test('fresh v4 database creates exactly the application tables', () async {
    final db = await DatabaseHelper.database;

    expect(await _applicationTableNames(db), _applicationTables);
  });

  test('fresh database stores the declared schema version', () async {
    final db = await DatabaseHelper.database;

    final rows = await db.rawQuery('PRAGMA user_version');
    expect(rows.single['user_version'], DatabaseHelper.schemaVersion);
  });

  test('fresh database seeds every declared achievement', () async {
    final db = await DatabaseHelper.database;

    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM achievements',
    );
    expect(rows.single['count'], kSeedAchievements.length);
  });

  test(
    'foreign-key enforcement is enabled for every opened database',
    () async {
      final db = await DatabaseHelper.database;

      final rows = await db.rawQuery('PRAGMA foreign_keys');
      expect(rows.single['foreign_keys'], 1);
    },
  );

  test('deleting a partner cascades through its configs and logs', () async {
    final db = await DatabaseHelper.database;
    const partnerId = 'partner-1';
    const configId = 'config-1';
    const logId = 'log-1';

    await db.insert('partners', {
      'id': partnerId,
      'nickname': 'Ta',
      'created_at': '2026-08-18T00:00:00.000Z',
      'updated_at': '2026-08-18T00:00:00.000Z',
    });
    await db.insert('reminder_configs', {
      'id': configId,
      'partner_id': partnerId,
      'category': 'weather',
      'created_at': '2026-08-18T00:00:00.000Z',
      'updated_at': '2026-08-18T00:00:00.000Z',
    });
    await db.insert('reminder_logs', {
      'id': logId,
      'config_id': configId,
      'partner_id': partnerId,
      'message': 'Take an umbrella',
      'triggered_at': '2026-08-18T00:00:00.000Z',
    });

    await db.delete('partners', where: 'id = ?', whereArgs: [partnerId]);

    expect(await _rowCount(db, 'reminder_configs', configId), 0);
    expect(await _rowCount(db, 'reminder_logs', logId), 0);
  });

  test('close is idempotent and does not open an unopened database', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'taworld-db-close-',
    );
    final databasePath = p.join(tempDirectory.path, 'unopened.db');

    try {
      await DatabaseHelper.configureForTesting(
        factory: databaseFactoryFfi,
        path: databasePath,
      );

      await DatabaseHelper.close();
      await DatabaseHelper.close();

      expect(File(databasePath).existsSync(), isFalse);
    } finally {
      await DatabaseHelper.resetForTesting();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  });

  test('upgrades a genuine v1 database through every AI migration', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'taworld-db-migration-',
    );
    final databasePath = p.join(tempDirectory.path, 'legacy.db');

    try {
      final legacyDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _createVersionOneFixture,
        ),
      );
      await legacyDatabase.close();

      await openTestDatabase(path: databasePath);
      final db = await DatabaseHelper.database;

      expect(await _applicationTableNames(db), _applicationTables);
      expect(await _applicationIndexNames(db), _applicationIndexes);
      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        DatabaseHelper.schemaVersion,
      );
    } finally {
      await DatabaseHelper.resetForTesting();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  });
}

Future<Set<String>> _applicationTableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master "
    "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<Set<String>> _applicationIndexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master "
    "WHERE type = 'index' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<int> _rowCount(Database db, String table, String id) async {
  final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
  return rows.length;
}

Future<void> _createVersionOneFixture(Database db, int version) async {
  await db.execute('''
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      nickname TEXT NOT NULL DEFAULT '',
      avatar_path TEXT,
      phone TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE partners (
      id TEXT PRIMARY KEY,
      nickname TEXT NOT NULL DEFAULT '',
      avatar_path TEXT,
      type TEXT NOT NULL DEFAULT 'friend',
      note TEXT,
      latitude REAL,
      longitude REAL,
      city TEXT,
      district TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE reminder_configs (
      id TEXT PRIMARY KEY,
      partner_id TEXT NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
      category TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      config TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE reminder_logs (
      id TEXT PRIMARY KEY,
      config_id TEXT NOT NULL REFERENCES reminder_configs(id) ON DELETE CASCADE,
      partner_id TEXT NOT NULL REFERENCES partners(id),
      message TEXT,
      status TEXT NOT NULL DEFAULT 'triggered',
      triggered_at TEXT NOT NULL,
      sent_at TEXT,
      confirmed_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE achievements (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      icon TEXT NOT NULL DEFAULT 'trophy',
      category TEXT NOT NULL DEFAULT 'general',
      unlock_condition TEXT NOT NULL DEFAULT '{}',
      points INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE user_achievements (
      id TEXT PRIMARY KEY,
      achievement_id TEXT NOT NULL REFERENCES achievements(id),
      progress INTEGER NOT NULL DEFAULT 0,
      unlocked INTEGER NOT NULL DEFAULT 0,
      unlocked_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE chat_history (
      id TEXT PRIMARY KEY,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute(
    'CREATE INDEX idx_reminder_configs_partner ON reminder_configs(partner_id)',
  );
  await db.execute(
    'CREATE INDEX idx_reminder_logs_config ON reminder_logs(config_id)',
  );
  await db.execute(
    'CREATE INDEX idx_reminder_logs_partner ON reminder_logs(partner_id)',
  );
  await db.execute(
    'CREATE INDEX idx_user_achievements_achievement '
    'ON user_achievements(achievement_id)',
  );
}
