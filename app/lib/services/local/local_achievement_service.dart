/// TaWorld 成就服务 — 本地版
///
/// 管理成就定义和用户进度。
library;

import 'dart:convert';
import '../../data/local/database_helper.dart';
import '../../data/models/achievement.dart';

abstract final class LocalAchievementService {
  static Future<void>? _refreshing;

  static Future<void> _refresh() =>
      _refreshing ??= _reconcile().whenComplete(() {
        _refreshing = null;
      });

  /// Derive progress from recorded actions. A system notification is not a
  /// completed act of care, and native actions do not pass through a UI sender.
  static Future<void> _reconcile() async {
    final db = await DatabaseHelper.database;
    // Read the small statistics snapshot without holding a write lock across
    // asynchronous reads; persist all derived progress in one atomic batch.
    final tx = db;
    final updates = db.batch();
    final categoryRows = await tx.rawQuery('''
        SELECT rc.category, COUNT(*) AS count FROM reminder_logs rl
        JOIN reminder_configs rc ON rc.id = rl.config_id
        WHERE rl.status = 'confirmed' GROUP BY rc.category
      ''');
    final counts = {
      for (final row in categoryRows)
        row['category'] as String: row['count'] as int,
    };
    final custom =
        (await tx.rawQuery(
              "SELECT COUNT(*) AS count FROM reminder_configs WHERE category = 'custom'",
            )).single['count']
            as int;
    final confirmed = await tx.query(
      'reminder_logs',
      columns: ['confirmed_at'],
      where: "status = 'confirmed' AND confirmed_at IS NOT NULL",
    );
    final days = <int>{};
    for (final row in confirmed) {
      final at = DateTime.tryParse(row['confirmed_at'] as String)?.toLocal();
      if (at != null) {
        days.add(
          DateTime.utc(at.year, at.month, at.day).millisecondsSinceEpoch ~/
              Duration.millisecondsPerDay,
        );
      }
    }
    final orderedDays = days.toList()..sort();
    var longest = 0, run = 0;
    int? previous;
    for (final day in orderedDays) {
      run = previous != null && day == previous + 1 ? run + 1 : 1;
      if (run > longest) longest = run;
      previous = day;
    }
    var recordedDays = 0;
    final now = DateTime.now();
    for (final person in await tx.query(
      'partners',
      where: "status = 'active'",
    )) {
      final created = DateTime.tryParse(person['created_at'] as String);
      if (created == null) continue;
      final age = now.difference(created).inDays;
      if (age > recordedDays) recordedDays = age;
    }
    for (final achievement in await tx.query('achievements')) {
      Map<String, dynamic> condition;
      try {
        condition =
            jsonDecode(achievement['unlock_condition'] as String)
                as Map<String, dynamic>;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
      final progress = switch (condition['type']) {
        'reminder_complete' => counts['weather'] ?? 0,
        'sleep_reminder_count' => counts['sleep'] ?? 0,
        'meal_reminder_count' => counts['meal'] ?? 0,
        'custom_reminder_count' => custom,
        'streak_days' => longest,
        'relationship_days' => recordedDays,
        _ => null,
      };
      if (progress == null) continue;
      final target = condition['target'] is num
          ? (condition['target'] as num).toInt()
          : 1;
      final unlocked = progress >= target;
      final rows = await tx.query(
        'user_achievements',
        where: 'achievement_id = ?',
        whereArgs: [achievement['id']],
      );
      final existing = rows.firstOrNull;
      if (existing?['progress'] == progress &&
          existing?['unlocked'] == (unlocked ? 1 : 0)) {
        continue;
      }
      final values = <String, Object?>{
        'progress': progress,
        'unlocked': unlocked ? 1 : 0,
        'unlocked_at': unlocked
            ? (existing?['unlocked_at'] ?? now.toUtc().toIso8601String())
            : null,
      };
      if (existing == null) {
        updates.insert('user_achievements', {
          'id': DatabaseHelper.newId(),
          'achievement_id': achievement['id'],
          ...values,
        });
      } else {
        updates.update(
          'user_achievements',
          values,
          where: 'achievement_id = ?',
          whereArgs: [achievement['id']],
        );
      }
    }
    await updates.commit(noResult: true);
  }

  /// 获取所有成就（含用户进度）
  ///
  /// [includeHidden] 是否包含隐藏的成就（如"双向奔赴"，单机版暂不展示）
  static Future<List<UserAchievement>> getAllWithProgress({
    bool includeHidden = false,
  }) async {
    await _refresh();
    final db = await DatabaseHelper.database;
    final whereClause = includeHidden ? '' : " WHERE a.category != 'mutual'";
    final rows = await db.rawQuery('''
      SELECT a.*, ua.id as ua_id, ua.progress, ua.unlocked, ua.unlocked_at
      FROM achievements a
      LEFT JOIN user_achievements ua ON ua.achievement_id = a.id
      $whereClause
      ORDER BY a.points ASC
    ''');

    return rows.map((row) {
      return UserAchievement(
        id: row['ua_id'] as String? ?? '',
        achievementId: row['id'] as String,
        progress: row['progress'] as int? ?? 0,
        unlocked: (row['unlocked'] as int? ?? 0) == 1,
        unlockedAt: row['unlocked_at'] != null
            ? DateTime.parse(row['unlocked_at'] as String)
            : null,
        achievementName: row['name'] as String?,
        achievementIcon: row['icon'] as String?,
        achievementDescription: row['category'] == 'milestone'
            ? '关心列表中至少一位人物已记录满100天'
            : row['description'] as String?,
        achievementPoints: row['points'] as int?,
      );
    }).toList();
  }

  /// 获取统计概览（排除隐藏成就）
  static Future<Map<String, dynamic>> getStats() async {
    await _refresh();
    final db = await DatabaseHelper.database;

    final totalResult = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM achievements WHERE category != 'mutual'",
    );
    final total = totalResult.first['cnt'] as int? ?? 0;

    final unlockedResult = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM user_achievements ua
      JOIN achievements a ON ua.achievement_id = a.id
      WHERE ua.unlocked = 1 AND a.category != 'mutual'
    ''');
    final unlocked = unlockedResult.first['cnt'] as int? ?? 0;

    return {'total': total, 'unlocked': unlocked, 'pending': total - unlocked};
  }
}
