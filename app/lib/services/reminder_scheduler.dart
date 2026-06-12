/// TaWorld 提醒调度器
///
/// 负责根据用户配置的提醒规则，使用 flutter_local_notifications
/// 的 zonedSchedule 精确定时调度通知。
///
/// 调度策略：
/// - sleep 提醒：每天在 target_sleep_time - advance_minutes 触发
/// - meal 提醒：每天在各 meal.target_time - advance_minutes 触发
/// - weather 提醒：每天早上 8:00 触发一次天气关注提醒
/// - custom 提醒：暂不支持自动调度（用户手动触发）
///
/// 通知 ID 策略：使用 configId.hashCode XOR 时间偏移量，确保唯一性。
library;

import '../data/models/reminder_config.dart';
import 'notification_service.dart';
import 'local/local_reminder_service.dart';
import 'local/partner_service.dart';

abstract final class ReminderScheduler {
  /// 初始化：调度所有启用的提醒
  ///
  /// 在 App 启动时调用，读取所有 enabled=1 的配置并调度。
  static Future<void> scheduleAll() async {
    // 先清除所有旧的调度通知
    await NotificationService.cancelAll();

    final configsByPartner = await LocalReminderService.getAllEnabledConfigs();
    final partners = await PartnerService.getAll();
    final partnerMap = {for (final p in partners) p.id: p};

    for (final entry in configsByPartner.entries) {
      final partnerId = entry.key;
      final configs = entry.value;
      final partner = partnerMap[partnerId];
      final partnerName = partner?.nickname ?? 'Ta';

      for (final config in configs) {
        await _scheduleConfig(config, partnerName);
      }
    }
  }

  /// 调度单个配置的所有提醒
  static Future<void> _scheduleConfig(
    ReminderConfig config,
    String partnerName,
  ) async {
    switch (config.category) {
      case 'sleep':
        await _scheduleSleepReminder(config, partnerName);
      case 'meal':
        await _scheduleMealReminder(config, partnerName);
      case 'weather':
        await _scheduleWeatherReminder(config, partnerName);
      case 'custom':
        // 自定义提醒不支持自动调度
        break;
    }
  }

  /// 调度睡觉提醒
  ///
  /// config 格式: { target_sleep_time: "23:00", advance_minutes: 30 }
  /// 调度时间 = target_sleep_time - advance_minutes，即 22:30
  /// 每天重复：如果今天的时间已过，则调度明天的。
  static Future<void> _scheduleSleepReminder(
    ReminderConfig config,
    String partnerName,
  ) async {
    final targetTime = config.config['target_sleep_time'] as String? ?? '23:00';
    final advanceMinutes = config.config['advance_minutes'] as int? ?? 30;

    final parts = targetTime.split(':');
    if (parts.length != 2) return;

    final hour = int.tryParse(parts[0]) ?? 23;
    final minute = int.tryParse(parts[1]) ?? 0;

    final now = DateTime.now();
    var scheduled = DateTime(
      now.year, now.month, now.day, hour, minute,
    ).subtract(Duration(minutes: advanceMinutes));

    // 如果今天的时间已过，调度明天
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    // 调度未来 7 天的（每天一个通知）
    for (int i = 0; i < 7; i++) {
      final dayScheduled = scheduled.add(Duration(days: i));
      if (dayScheduled.isBefore(now)) continue;

      final id = _makeId(config.id, i);
      final body = '快到$partnerName的睡觉时间了，提醒Ta早点休息吧';
      await NotificationService.schedule(
        id: id,
        title: '🌙 睡觉提醒',
        body: body,
        scheduledTime: dayScheduled,
        payload: 'configId:${config.id}',
      );

      // 预创建调度日志
      await LocalReminderService.createScheduledLog(
        configId: config.id,
        partnerId: config.partnerId,
        message: body,
        scheduledTime: dayScheduled,
      );
    }
  }

  /// 调度吃饭提醒
  ///
  /// config 格式: { meals: [{ name: "早餐", target_time: "08:00", advance_minutes: 15 }, ...] }
  static Future<void> _scheduleMealReminder(
    ReminderConfig config,
    String partnerName,
  ) async {
    final meals = config.config['meals'] as List?;
    if (meals == null || meals.isEmpty) return;

    final now = DateTime.now();

    for (final meal in meals) {
      if (meal is! Map) continue;
      final name = meal['name'] as String? ?? '吃饭';
      final targetTime = meal['target_time'] as String? ?? '12:00';
      final advanceMinutes = meal['advance_minutes'] as int? ?? 15;

      final parts = targetTime.split(':');
      if (parts.length != 2) continue;

      final hour = int.tryParse(parts[0]) ?? 12;
      final minute = int.tryParse(parts[1]) ?? 0;

      var scheduled = DateTime(
        now.year, now.month, now.day, hour, minute,
      ).subtract(Duration(minutes: advanceMinutes));

      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      // 调度未来 7 天
      for (int i = 0; i < 7; i++) {
        final dayScheduled = scheduled.add(Duration(days: i));
        if (dayScheduled.isBefore(now)) continue;

        final id = _makeId('${config.id}_$name', i);
        final body = '到$name时间了，提醒$partnerName按时吃饭吧';
        await NotificationService.schedule(
          id: id,
          title: '🍚 $name提醒',
          body: body,
          scheduledTime: dayScheduled,
          payload: 'configId:${config.id}',
        );

        // 预创建调度日志
        await LocalReminderService.createScheduledLog(
          configId: config.id,
          partnerId: config.partnerId,
          message: body,
          scheduledTime: dayScheduled,
        );
      }
    }
  }

  /// 调度天气提醒
  ///
  /// 每天早上 8:00 提醒用户关注对方所在地的天气
  static Future<void> _scheduleWeatherReminder(
    ReminderConfig config,
    String partnerName,
  ) async {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, 8, 0);

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    // 调度未来 7 天
    for (int i = 0; i < 7; i++) {
      final dayScheduled = scheduled.add(Duration(days: i));
      if (dayScheduled.isBefore(now)) continue;

      final id = _makeId('${config.id}_weather', i);
      final body = '新的一天开始了，看看$partnerName那边的天气吧';
      await NotificationService.schedule(
        id: id,
        title: '🌦️ 天气关注',
        body: body,
        scheduledTime: dayScheduled,
        payload: 'configId:${config.id}',
      );

      // 预创建调度日志
      await LocalReminderService.createScheduledLog(
        configId: config.id,
        partnerId: config.partnerId,
        message: body,
        scheduledTime: dayScheduled,
      );
    }
  }

  /// 生成唯一的通知 ID
  ///
  /// 基于配置 ID 的 hashCode 和天数偏移量，确保每个调度有唯一 ID
  static int _makeId(String configKey, int dayOffset) {
    return (configKey.hashCode ^ (dayOffset * 1000)).abs() % 2147483647;
  }

  /// 重新调度某个配置的通知（配置变更时调用）
  static Future<void> rescheduleConfig(String configId) async {
    // 取消全部旧调度并重新调度
    await scheduleAll();
  }

  /// 取消某个配置的所有调度通知
  ///
  /// 由于我们无法精确知道已调度的通知 ID，
  /// 采用"取消全部再重新调度"的策略。
  static Future<void> cancelConfig(String configId) async {
    // 简化策略：取消全部再重新调度剩余的
    await scheduleAll();
  }
}
