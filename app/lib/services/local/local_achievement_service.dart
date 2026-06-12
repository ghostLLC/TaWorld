/// TaWorld 成就服务 — 本地版
///
/// 管理成就定义和用户进度。
library;

import '../../data/local/database_helper.dart';
import '../../data/models/achievement.dart';

abstract final class LocalAchievementService {
  /// 获取所有成就（含用户进度）
  ///
  /// [includeHidden] 是否包含隐藏的成就（如"双向奔赴"，单机版暂不展示）
  static Future<List<UserAchievement>> getAllWithProgress({bool includeHidden = false}) async {
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
        achievementDescription: row['description'] as String?,
        achievementPoints: row['points'] as int?,
      );
    }).toList();
  }

  /// 获取统计概览（排除隐藏成就）
  static Future<Map<String, dynamic>> getStats() async {
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

    return {
      'total': total,
      'unlocked': unlocked,
      'pending': total - unlocked,
    };
  }
}
