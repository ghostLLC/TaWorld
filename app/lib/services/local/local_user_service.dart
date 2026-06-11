/// TaWorld 本地用户服务
///
/// 管理单机版唯一的本地用户记录。
library;

import '../../data/local/database_helper.dart';
import '../../data/models/user.dart';

abstract final class LocalUserService {
  /// 获取本地用户（可能为 null 如果还没设置）
  static Future<LocalUser?> getUser() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('users', limit: 1);
    if (rows.isEmpty) return null;
    return LocalUser.fromMap(rows.first);
  }

  /// 首次创建本地用户
  static Future<LocalUser> createUser({
    required String nickname,
    String? phone,
  }) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    final user = LocalUser(
      id: DatabaseHelper.newId(),
      nickname: nickname,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('users', user.toMap());
    return user;
  }

  /// 更新昵称
  static Future<void> updateNickname(String nickname) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'users',
      {'nickname': nickname, 'updated_at': DateTime.now().toIso8601String()},
    );
  }

  /// 更新头像（本地文件路径）
  static Future<void> updateAvatar(String filePath) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'users',
      {'avatar_path': filePath, 'updated_at': DateTime.now().toIso8601String()},
    );
  }

  /// 检查是否已创建用户
  static Future<bool> hasUser() async {
    final user = await getUser();
    return user != null;
  }

  /// 获取用户统计数据
  /// 返回 { partnerCount, reminderCount, streakDays }
  static Future<Map<String, dynamic>> getStats() async {
    final db = await DatabaseHelper.database;

    // 关心的人数量
    final partnerResult = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM partners WHERE status = 'active'",
    );
    final partnerCount = partnerResult.first['cnt'] as int? ?? 0;

    // 总提醒次数
    final reminderResult = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM reminder_logs WHERE status IN ('sent', 'confirmed')",
    );
    final reminderCount = reminderResult.first['cnt'] as int? ?? 0;

    // 连续活跃天数（从今天往回数，最多30天）
    int streakDays = 0;
    final now = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final day = now.subtract(Duration(days: i));
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM reminder_logs '
        'WHERE triggered_at >= ? AND triggered_at < ?',
        [dayStart.toIso8601String(), dayEnd.toIso8601String()],
      );
      final count = result.first['cnt'] as int? ?? 0;
      if (count > 0) {
        streakDays++;
      } else {
        break;
      }
    }

    return {
      'partnerCount': partnerCount,
      'reminderCount': reminderCount,
      'streakDays': streakDays,
    };
  }
}
