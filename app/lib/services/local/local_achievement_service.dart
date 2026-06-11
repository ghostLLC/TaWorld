/// TaWorld 成就服务 — 本地版
///
/// 管理成就定义和用户进度。
library;

import '../../data/local/database_helper.dart';
import '../../data/models/achievement.dart';

abstract final class LocalAchievementService {
  /// 获取所有成就（含用户进度）
  static Future<List<UserAchievement>> getAllWithProgress() async {
    final db = await DatabaseHelper.database;
    final rows = await db.rawQuery('''
      SELECT a.*, ua.id as ua_id, ua.progress, ua.unlocked, ua.unlocked_at
      FROM achievements a
      LEFT JOIN user_achievements ua ON ua.achievement_id = a.id
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
        achievementDescription: row['description'] as String?,
        achievementPoints: row['points'] as int?,
      );
    }).toList();
  }

  /// 获取统计概览
  static Future<Map<String, dynamic>> getStats() async {
    final db = await DatabaseHelper.database;

    final totalResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM achievements');
    final total = totalResult.first['cnt'] as int? ?? 0;

    final unlockedResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM user_achievements WHERE unlocked = 1',
    );
    final unlocked = unlockedResult.first['cnt'] as int? ?? 0;

    final pointsResult = await db.rawQuery('''
      SELECT COALESCE(SUM(a.points), 0) as total_points
      FROM user_achievements ua
      JOIN achievements a ON ua.achievement_id = a.id
      WHERE ua.unlocked = 1
    ''');
    final totalPoints = pointsResult.first['total_points'] as int? ?? 0;

    return {
      'total': total,
      'unlocked': unlocked,
      'pending': total - unlocked,
      'totalPoints': totalPoints,
    };
  }
}
