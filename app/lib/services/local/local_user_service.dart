/// TaWorld 本地用户服务
///
/// 管理单机版唯一的本地用户记录。
library;

import '../../data/local/database_helper.dart';
import '../care_activity_service.dart';
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
    await db.update('users', {
      'nickname': nickname,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// 更新头像（本地文件路径）
  static Future<void> updateAvatar(String filePath) async {
    final db = await DatabaseHelper.database;
    await db.update('users', {
      'avatar_path': filePath,
      'updated_at': DateTime.now().toIso8601String(),
    });
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

    // 只有用户明确确认的记录才计入关心次数。
    final reminderResult = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM reminder_logs WHERE status = 'confirmed'",
    );
    final reminderCount = reminderResult.first['cnt'] as int? ?? 0;

    // 按用户本地日期计算连续确认天数。
    final streakDays = await CareActivityService.streakDays();

    return {
      'partnerCount': partnerCount,
      'reminderCount': reminderCount,
      'streakDays': streakDays,
    };
  }
}
