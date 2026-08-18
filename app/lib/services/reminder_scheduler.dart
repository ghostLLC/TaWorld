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

import 'dart:developer' as dev;

import 'package:timezone/timezone.dart' as tz;

import '../data/models/reminder_config.dart';
import 'notification_service.dart';
import 'local/local_reminder_service.dart';
import 'local/partner_service.dart';
import 'reminder_schedule_calculator.dart';
import 'timezone_service.dart';

abstract final class ReminderScheduler {
  /// 初始化：调度所有启用的提醒
  ///
  /// 在 App 启动时调用，读取所有 enabled=1 的配置并调度。
  static Future<void> scheduleAll() async {
    if (!TimezoneService.isInitialized || !NotificationService.isInitialized) {
      dev.log(
        '跳过提醒调度：设备时区或通知服务尚未初始化',
        name: 'TaWorld',
      );
      return;
    }

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
    final occurrences = ReminderScheduleCalculator.build(
      config: config,
      partnerName: partnerName,
      now: tz.TZDateTime.now(tz.local),
    );

    for (final occurrence in occurrences) {
      await NotificationService.schedule(
        id: occurrence.notificationId,
        title: occurrence.title,
        body: occurrence.body,
        scheduledTime: occurrence.scheduledTime,
        payload: occurrence.payload,
      );

      await LocalReminderService.createScheduledLog(
        configId: config.id,
        partnerId: config.partnerId,
        message: occurrence.body,
        scheduledTime: occurrence.scheduledTime,
      );
    }
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
