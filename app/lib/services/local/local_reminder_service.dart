/// TaWorld 提醒服务 — 本地版
///
/// 管理提醒配置、提醒日志、一键提醒、提醒统计。
library;

import 'dart:convert';
import '../../data/local/database_helper.dart';
import '../../data/models/reminder_config.dart';
import '../../data/models/reminder_log.dart';
import '../weather_service.dart';
import '../notification_service.dart';

abstract final class LocalReminderService {
  // ==================== 提醒配置 ====================

  /// 获取某人的所有提醒配置
  static Future<List<ReminderConfig>> getConfigs(String partnerId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_configs',
      where: 'partner_id = ?',
      whereArgs: [partnerId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ReminderConfig.fromMap).toList();
  }

  /// 获取所有启用的提醒配置（按 partnerId 分组）
  static Future<Map<String, List<ReminderConfig>>> getAllEnabledConfigs() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_configs',
      where: 'enabled = 1',
      orderBy: 'created_at ASC',
    );
    final configs = rows.map(ReminderConfig.fromMap).toList();
    final grouped = <String, List<ReminderConfig>>{};
    for (final c in configs) {
      grouped.putIfAbsent(c.partnerId, () => []).add(c);
    }
    return grouped;
  }

  /// 创建提醒配置
  static Future<ReminderConfig> createConfig({
    required String partnerId,
    required String category,
    Map<String, dynamic>? config,
    bool enabled = true,
  }) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    final rc = ReminderConfig(
      id: DatabaseHelper.newId(),
      partnerId: partnerId,
      category: category,
      enabled: enabled,
      config: config ?? ReminderConfig.defaultConfigFor(category),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('reminder_configs', rc.toMap());
    return rc;
  }

  /// 更新提醒配置
  static Future<void> updateConfig(String id, {
    bool? enabled,
    Map<String, dynamic>? config,
  }) async {
    final db = await DatabaseHelper.database;
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (enabled != null) data['enabled'] = enabled ? 1 : 0;
    if (config != null) data['config'] = jsonEncode(config);
    await db.update('reminder_configs', data, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除提醒配置
  static Future<void> deleteConfig(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete('reminder_configs', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 提醒日志 ====================

  /// 一键提醒：创建日志 + 返回消息
  static Future<ReminderLog> sendReminder(String configId) async {
    final db = await DatabaseHelper.database;
    // 获取配置
    final configRows = await db.query(
      'reminder_configs',
      where: 'id = ?',
      whereArgs: [configId],
    );
    if (configRows.isEmpty) throw Exception('提醒配置不存在');
    final config = ReminderConfig.fromMap(configRows.first);

    final now = DateTime.now();
    // Weather integration: for weather category, try to get live weather data
    String message;
    if (config.category == 'weather') {
      message = await _getWeatherMessage(config);
    } else {
      message = _generateMessage(config);
    }

    final log = ReminderLog(
      id: DatabaseHelper.newId(),
      configId: configId,
      partnerId: config.partnerId,
      message: message,
      status: 'sent',
      triggeredAt: now,
      sentAt: now,
    );
    await db.insert('reminder_logs', log.toMap());

    // Push notification
    await NotificationService.show(
      id: log.id.hashCode,
      title: '关心提醒',
      body: message,
      payload: log.id,
    );

    // 更新成就进度
    await _updateAchievementOnSend(config);

    return log;
  }

  /// 确认提醒
  static Future<void> confirmReminder(String logId) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'reminder_logs',
      {'status': 'confirmed', 'confirmed_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [logId],
    );
  }

  /// 获取某配置的提醒日志
  static Future<List<ReminderLog>> getLogs(String configId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_logs',
      where: 'config_id = ?',
      whereArgs: [configId],
      orderBy: 'triggered_at DESC',
    );
    return rows.map(ReminderLog.fromMap).toList();
  }

  /// 获取所有提醒日志
  static Future<List<ReminderLog>> getAllLogs({int limit = 50}) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_logs',
      orderBy: 'triggered_at DESC',
      limit: limit,
    );
    return rows.map(ReminderLog.fromMap).toList();
  }

  /// 获取提醒统计
  static Future<Map<String, dynamic>> getStats() async {
    final db = await DatabaseHelper.database;

    final totalResult = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM reminder_logs WHERE status IN ('sent', 'confirmed')",
    );
    final totalCount = totalResult.first['cnt'] as int? ?? 0;

    // 按类别统计
    final categoryStats = await db.rawQuery('''
      SELECT rc.category, COUNT(*) as cnt
      FROM reminder_logs rl
      JOIN reminder_configs rc ON rl.config_id = rc.id
      WHERE rl.status IN ('sent', 'confirmed')
      GROUP BY rc.category
    ''');

    final byCategory = <String, int>{};
    for (final row in categoryStats) {
      byCategory[row['category'] as String] = row['cnt'] as int? ?? 0;
    }

    // 连续天数
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
      'totalCount': totalCount,
      'byCategory': byCategory,
      'streakDays': streakDays,
    };
  }

  /// 获取天气提醒消息（查询partner所在地实时天气）
  static Future<String> _getWeatherMessage(ReminderConfig config) async {
    try {
      // Get the partner to check for location
      final db = await DatabaseHelper.database;
      final partnerRows = await db.query(
        'partners',
        where: 'id = ?',
        whereArgs: [config.partnerId],
      );
      if (partnerRows.isEmpty) return _generateMessage(config);

      final lat = partnerRows.first['latitude'] as double?;
      final lng = partnerRows.first['longitude'] as double?;
      if (lat == null || lng == null) return _generateMessage(config);

      // Query weather
      final weather = await WeatherService.getCurrentWeather(lng, lat);
      if (weather == null) return _generateMessage(config);

      // Check conditions from config
      final conditions = (config.config['notify_conditions'] as List?)
          ?.cast<String>() ?? ['rain', 'snow', 'extreme_cold', 'extreme_heat'];
      final check = WeatherService.checkConditions(weather, conditions);

      if (check.shouldRemind && check.message != null) {
        return check.message!;
      }
      // Weather is fine, generate a general weather update message
      return 'Ta那边现在${weather.text}，${weather.temp}°C 💝';
    } catch (_) {
      return _generateMessage(config);
    }
  }

  /// 生成提醒消息
  static String _generateMessage(ReminderConfig config) {
    return switch (config.category) {
      'weather' => '天气有变化，提醒Ta注意哦 🌦️',
      'sleep' => '快到睡觉时间了，提醒Ta早点休息 🌙',
      'meal' => '到饭点了，提醒Ta按时吃饭 🍚',
      'custom' => '想Ta了就告诉Ta吧 💝',
      _ => '记得关心一下Ta 💝',
    };
  }

  /// 发送提醒后更新成就
  static Future<void> _updateAchievementOnSend(ReminderConfig config) async {
    final db = await DatabaseHelper.database;
    final achievements = await db.query('achievements');

    for (final a in achievements) {
      final condition = jsonDecode(a['unlock_condition'] as String) as Map<String, dynamic>;
      final type = condition['type'] as String? ?? '';
      final target = condition['target'] as int? ?? 1;

      bool shouldUpdate = false;

      // 天气提醒首次完成
      if (type == 'reminder_complete' && config.category == 'weather') {
        shouldUpdate = true;
      }
      // 睡觉提醒计数
      if (type == 'sleep_reminder_count' && config.category == 'sleep') {
        shouldUpdate = true;
      }
      // 吃饭提醒计数
      if (type == 'meal_reminder_count' && config.category == 'meal') {
        shouldUpdate = true;
      }
      // 自定义提醒计数
      if (type == 'custom_reminder_count' && config.category == 'custom') {
        shouldUpdate = true;
      }

      if (shouldUpdate) {
        // 查找或创建 user_achievement
        var uaRows = await db.query(
          'user_achievements',
          where: 'achievement_id = ?',
          whereArgs: [a['id']],
        );

        if (uaRows.isEmpty) {
          await db.insert('user_achievements', {
            'id': DatabaseHelper.newId(),
            'achievement_id': a['id'],
            'progress': 1,
            'unlocked': 1 >= target ? 1 : 0,
            'unlocked_at': 1 >= target ? DateTime.now().toIso8601String() : null,
          });
        } else {
          final ua = uaRows.first;
          final unlocked = (ua['unlocked'] as int) == 1;
          if (unlocked) continue;

          final newProgress = (ua['progress'] as int) + 1;
          await db.update(
            'user_achievements',
            {
              'progress': newProgress,
              'unlocked': newProgress >= target ? 1 : 0,
              'unlocked_at': newProgress >= target ? DateTime.now().toIso8601String() : null,
            },
            where: 'id = ?',
            whereArgs: [ua['id']],
          );
        }
      }
    }

    // 检查 streak_days 和 relationship_days 类型
    await _checkStreakAndRelationshipAchievements();
  }

  /// 检查连续天数和关系天数成就
  static Future<void> _checkStreakAndRelationshipAchievements() async {
    final db = await DatabaseHelper.database;

    // streak_days
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

    final streakAchievements = await db.rawQuery(
      "SELECT * FROM achievements WHERE json_extract(unlock_condition, '\$.type') = 'streak_days'",
    );
    for (final a in streakAchievements) {
      final condition = jsonDecode(a['unlock_condition'] as String) as Map<String, dynamic>;
      final target = condition['target'] as int? ?? 7;
      await _updateAbsoluteAchievement(a['id'] as String, streakDays, target);
    }

    // relationship_days
    final partners = await db.query(
      'partners',
      where: "status = 'active'",
    );
    int maxDays = 0;
    for (final p in partners) {
      final days = DateTime.now()
          .difference(DateTime.parse(p['created_at'] as String))
          .inDays;
      if (days > maxDays) maxDays = days;
    }

    final relAchievements = await db.rawQuery(
      "SELECT * FROM achievements WHERE json_extract(unlock_condition, '\$.type') = 'relationship_days'",
    );
    for (final a in relAchievements) {
      final condition = jsonDecode(a['unlock_condition'] as String) as Map<String, dynamic>;
      final target = condition['target'] as int? ?? 100;
      await _updateAbsoluteAchievement(a['id'] as String, maxDays, target);
    }
  }

  /// 更新绝对进度型成就
  static Future<void> _updateAbsoluteAchievement(
    String achievementId,
    int progress,
    int target,
  ) async {
    final db = await DatabaseHelper.database;
    var uaRows = await db.query(
      'user_achievements',
      where: 'achievement_id = ?',
      whereArgs: [achievementId],
    );

    if (uaRows.isEmpty) {
      await db.insert('user_achievements', {
        'id': DatabaseHelper.newId(),
        'achievement_id': achievementId,
        'progress': progress,
        'unlocked': progress >= target ? 1 : 0,
        'unlocked_at': progress >= target ? DateTime.now().toIso8601String() : null,
      });
    } else {
      final ua = uaRows.first;
      final unlocked = (ua['unlocked'] as int) == 1;
      if (unlocked) return;

      final currentProgress = ua['progress'] as int;
      final newProgress = currentProgress > progress ? currentProgress : progress;
      await db.update(
        'user_achievements',
        {
          'progress': newProgress,
          'unlocked': newProgress >= target ? 1 : 0,
          'unlocked_at': newProgress >= target ? DateTime.now().toIso8601String() : null,
        },
        where: 'id = ?',
        whereArgs: [ua['id']],
      );
    }
  }
}
