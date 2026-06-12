/// TaWorld 本地数据库管理
///
/// SQLite 数据库单例管理，建表、种子数据、升级迁移。
library;

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/achievement.dart';

class DatabaseHelper {
  static Database? _database;
  static const _dbName = 'taworld.db';
  static const _dbVersion = 4;
  static const _uuid = Uuid();

  /// 获取数据库实例
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 用户表（仅一条本地记录）
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

    // 关心的人
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

    // 提醒配置
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

    // 提醒日志
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

    // 成就定义
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

    // 用户成就进度
    await db.execute('''
      CREATE TABLE user_achievements (
        id TEXT PRIMARY KEY,
        achievement_id TEXT NOT NULL REFERENCES achievements(id),
        progress INTEGER NOT NULL DEFAULT 0,
        unlocked INTEGER NOT NULL DEFAULT 0,
        unlocked_at TEXT
      )
    ''');

    // AI 对话历史
    await db.execute('''
      CREATE TABLE chat_history (
        id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // AI 主动消息队列（后台评估后写入，前台打开时消费）
    await db.execute('''
      CREATE TABLE ai_pending_messages (
        id TEXT PRIMARY KEY,
        partner_id TEXT,
        category TEXT NOT NULL,
        message TEXT NOT NULL,
        confidence REAL DEFAULT 0.5,
        status TEXT DEFAULT 'pending',
        created_at TEXT NOT NULL,
        shown_at TEXT
      )
    ''');

    // AI Wiki 事实表（记忆系统 Wiki 层）
    await db.execute('''
      CREATE TABLE ai_wiki_facts (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        entity_id TEXT,
        content TEXT NOT NULL,
        source TEXT DEFAULT 'chat',
        importance REAL DEFAULT 0.5,
        strength REAL DEFAULT 1.0,
        access_count INTEGER DEFAULT 0,
        last_accessed TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 对话摘要表（记忆系统摘要层）
    await db.execute('''
      CREATE TABLE ai_conversation_summaries (
        id TEXT PRIMARY KEY,
        summary TEXT NOT NULL,
        message_count INTEGER,
        date TEXT NOT NULL,
        topics TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 对话 chunks 表（记忆系统 RAG 层）
    await db.execute('''
      CREATE TABLE conversation_chunks (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        role TEXT NOT NULL,
        conversation_date TEXT,
        topics TEXT,
        embedding BLOB,
        created_at TEXT NOT NULL
      )
    ''');

    // 索引
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
      'CREATE INDEX idx_user_achievements_achievement ON user_achievements(achievement_id)',
    );
    await db.execute(
      'CREATE INDEX idx_ai_wiki_facts_category ON ai_wiki_facts(category)',
    );
    await db.execute(
      'CREATE INDEX idx_ai_wiki_facts_entity ON ai_wiki_facts(entity_id)',
    );
    await db.execute(
      'CREATE INDEX idx_conversation_chunks_date ON conversation_chunks(conversation_date)',
    );

    // 插入成就种子数据
    await _seedAchievements(db);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_pending_messages (
          id TEXT PRIMARY KEY,
          partner_id TEXT,
          category TEXT NOT NULL,
          message TEXT NOT NULL,
          confidence REAL DEFAULT 0.5,
          status TEXT DEFAULT 'pending',
          created_at TEXT NOT NULL,
          shown_at TEXT
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_wiki_facts (
          id TEXT PRIMARY KEY,
          category TEXT NOT NULL,
          entity_id TEXT,
          content TEXT NOT NULL,
          source TEXT DEFAULT 'chat',
          importance REAL DEFAULT 0.5,
          strength REAL DEFAULT 1.0,
          access_count INTEGER DEFAULT 0,
          last_accessed TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_conversation_summaries (
          id TEXT PRIMARY KEY,
          summary TEXT NOT NULL,
          message_count INTEGER,
          date TEXT NOT NULL,
          topics TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ai_wiki_facts_category ON ai_wiki_facts(category)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ai_wiki_facts_entity ON ai_wiki_facts(entity_id)',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS conversation_chunks (
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          role TEXT NOT NULL,
          conversation_date TEXT,
          topics TEXT,
          embedding BLOB,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_conversation_chunks_date ON conversation_chunks(conversation_date)',
      );
    }
  }

  static Future<void> _seedAchievements(Database db) async {
    final batch = db.batch();
    for (final seed in kSeedAchievements) {
      batch.insert('achievements', {
        'id': _uuid.v4(),
        ...seed,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 生成新的 UUID
  static String newId() => _uuid.v4();

  /// 关闭数据库（测试/清理用）
  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
