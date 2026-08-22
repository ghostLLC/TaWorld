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

import 'dart:async';
import 'dart:developer' as dev;

import 'package:timezone/timezone.dart' as tz;

import '../data/models/reminder_config.dart';
import '../data/models/partner.dart';
import 'notification_service.dart';
import 'local/local_reminder_service.dart';
import 'local/partner_service.dart';
import 'reminder_schedule_calculator.dart';
import 'reminder_occurrence_service.dart';
import 'timezone_service.dart';

typedef ReminderSchedulePlanBuilder<T> = FutureOr<List<T>> Function();
typedef ReminderScheduleAction<T> = Future<void> Function(T item);

/// Raised when the initial schedule attempt and its complete-plan retry fail.
class ReminderScheduleBatchException implements Exception {
  const ReminderScheduleBatchException({
    required this.firstFailure,
    required this.firstStackTrace,
    required this.retryFailure,
    required this.retryStackTrace,
  });

  final Object firstFailure;
  final StackTrace firstStackTrace;
  final Object retryFailure;
  final StackTrace retryStackTrace;

  @override
  String toString() {
    return 'ReminderScheduleBatchException: initial scheduling failed: '
        '$firstFailure; complete-plan retry failed: $retryFailure';
  }
}

/// Executes a precomputed notification plan atomically enough to recover from
/// a mid-batch scheduling failure.
///
/// The plan builder always runs before [cancelAll]. If a schedule action fails,
/// the complete plan is replayed once. `zonedSchedule` uses the notification
/// ID as the replacement key, so replaying an already scheduled item is
/// idempotent.
class ReminderScheduleBatchExecutor<T> {
  const ReminderScheduleBatchExecutor({
    required this.buildPlan,
    required this.cancelAll,
    required this.schedule,
  });

  final ReminderSchedulePlanBuilder<T> buildPlan;
  final Future<void> Function() cancelAll;
  final ReminderScheduleAction<T> schedule;

  Future<List<T>> execute() async {
    final plan = List<T>.unmodifiable(await buildPlan());
    await cancelAll();

    try {
      await _executePlan(plan);
    } catch (firstFailure, firstStackTrace) {
      try {
        await _executePlan(plan);
      } catch (retryFailure, retryStackTrace) {
        Error.throwWithStackTrace(
          ReminderScheduleBatchException(
            firstFailure: firstFailure,
            firstStackTrace: firstStackTrace,
            retryFailure: retryFailure,
            retryStackTrace: retryStackTrace,
          ),
          retryStackTrace,
        );
      }
    }

    return plan;
  }

  Future<void> _executePlan(List<T> plan) async {
    for (final item in plan) {
      await schedule(item);
    }
  }
}

class _PlannedReminder {
  const _PlannedReminder({
    required this.config,
    required this.occurrence,
    required this.occurrenceId,
  });

  final ReminderConfig config;
  final ReminderOccurrence occurrence;
  final String occurrenceId;
}

abstract final class ReminderScheduler {
  /// 初始化：调度所有启用的提醒
  ///
  /// 在 App 启动时调用，读取所有 enabled=1 的配置并调度。
  static Future<void> scheduleAll() async {
    if (!TimezoneService.isInitialized || !NotificationService.isInitialized) {
      dev.log('跳过提醒调度：设备时区或通知服务尚未初始化', name: 'TaWorld');
      return;
    }

    final executor = ReminderScheduleBatchExecutor<_PlannedReminder>(
      buildPlan: _buildSchedulePlan,
      cancelAll: NotificationService.cancelAll,
      schedule: (planned) => NotificationService.schedule(
        id: planned.occurrence.notificationId,
        title: planned.occurrence.title,
        body: planned.occurrence.body,
        scheduledTime: planned.occurrence.scheduledTime,
        payload: 'occurrenceId:${planned.occurrenceId}',
      ),
    );
    final plan = await executor.execute();

    // Write logs only after the complete notification plan succeeds. This
    // prevents a partial first attempt from duplicating logs on retry.
    for (final planned in plan) {
      await LocalReminderService.createScheduledLog(
        configId: planned.config.id,
        partnerId: planned.config.partnerId,
        message: planned.occurrence.body,
        scheduledTime: planned.occurrence.scheduledTime,
      );
    }
  }

  /// Calculates and validates the complete notification plan before any
  /// existing notification is cancelled.
  static Future<List<_PlannedReminder>> _buildSchedulePlan() async {
    final configs = await LocalReminderService.getAllEnabledConfigList();
    final partners = await PartnerService.getAll();
    final partnerMap = {for (final p in partners) p.id: p};
    final now = tz.TZDateTime.now(tz.local);
    final plan = <_PlannedReminder>[];
    final notificationIds = <int>{};

    for (final config in configs) {
      final partner = config.isSelfReminder
          ? null
          : partnerMap[config.partnerId];
      if (!config.isSelfReminder && partner == null) continue;
      final occurrences = config.isSelfReminder
          ? ReminderScheduleCalculator.build(
              config: config,
              partnerName: '你',
              now: now,
            )
          : calculateOccurrences(config: config, partner: partner!, now: now);
      for (final occurrence in occurrences) {
        if (!notificationIds.add(occurrence.notificationId)) {
          throw StateError('提醒调度计划包含重复通知 ID: ${occurrence.notificationId}');
        }
        final record = await ReminderOccurrenceService.ensureScheduled(
          config: config,
          scheduledFor: occurrence.scheduledTime,
          message: occurrence.body,
        );
        plan.add(
          _PlannedReminder(
            config: config,
            occurrence: occurrence,
            occurrenceId: record.id,
          ),
        );
      }
    }

    return plan;
  }

  /// Deterministically binds a reminder to its partner profile before
  /// scheduling. Keeping this boundary pure prevents the scheduler from
  /// silently falling back to the device zone for overseas partners.
  static List<ReminderOccurrence> calculateOccurrences({
    required ReminderConfig config,
    required Partner partner,
    required tz.TZDateTime now,
    int occurrenceCount = 7,
  }) {
    return ReminderScheduleCalculator.build(
      config: config,
      partnerName: partner.nickname,
      partnerTimeZoneId: partner.timezoneConfirmed ? partner.timezoneId : null,
      now: now,
      occurrenceCount: occurrenceCount,
    );
  }

  static List<ReminderOccurrence> calculateSelfOccurrences({
    required ReminderConfig config,
    required tz.TZDateTime now,
    int occurrenceCount = 7,
  }) {
    return ReminderScheduleCalculator.build(
      config: config,
      partnerName: '你',
      now: now,
      occurrenceCount: occurrenceCount,
    );
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
