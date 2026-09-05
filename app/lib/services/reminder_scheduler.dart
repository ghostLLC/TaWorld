/// Reconciles future reminder plans without removing visible notifications.
/// Stable IDs identify each actual instant. Android publication, buttons and
/// reboot restoration are owned by the local notification plugin.
/// Custom reminders support one fixed instant or daily/weekday wall times.
library;

import 'dart:io';

import 'dart:async';
import 'dart:convert';
import '../data/local/database_helper.dart';
import 'notification_ledger.dart';
import 'native_notification_bridge.dart';

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
  static Future<void>? _inFlight;
  static bool _rerun = false;

  static Future<void> scheduleAll() {
    if (_inFlight != null) {
      _rerun = true;
      return _inFlight!;
    }
    return _inFlight = (() async {
      do {
        _rerun = false;
        await _synchronize();
      } while (_rerun);
    })().whenComplete(() => _inFlight = null);
  }

  static Future<void> _synchronize() async {
    if (!TimezoneService.isInitialized || !NotificationService.isInitialized) {
      return;
    }
    final db = await DatabaseHelper.database;
    final owner = '$pid:${DatabaseHelper.newId()}';
    final now = DateTime.now().toUtc();
    final waitingSince = DateTime.now();
    var acquired = false;
    while (!acquired) {
      final now = DateTime.now().toUtc();
      acquired = await db.transaction((tx) async {
        final rows = await tx.query(
          'runtime_locks',
          where: 'name = ?',
          whereArgs: ['reminder_schedule'],
        );
        if (rows.isNotEmpty) {
          final row = rows.single;
          final holder = int.tryParse(
            (row['owner'] as String).split(':').first,
          );
          final expires = DateTime.tryParse(row['expires_at'] as String);
          // Android workers and UI isolates share the app UID. A missing process
          // cannot own an active schedule; old unqualified development leases
          // also cannot survive an application upgrade.
          final abandoned =
              holder == null ||
              (Platform.isAndroid && !Directory('/proc/$holder').existsSync());
          if (!abandoned && expires != null && expires.isAfter(now)) {
            return false;
          }
          await tx.delete(
            'runtime_locks',
            where: 'name = ?',
            whereArgs: ['reminder_schedule'],
          );
        }
        await tx.insert('runtime_locks', {
          'name': 'reminder_schedule',
          'owner': owner,
          'expires_at': now.add(const Duration(minutes: 2)).toIso8601String(),
        });
        return true;
      });
      if (!acquired) {
        if (DateTime.now().difference(waitingSince) >
            const Duration(minutes: 2)) {
          throw StateError('提醒正在由另一任务更新，请稍后重试');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    final renewal = Timer.periodic(const Duration(seconds: 30), (_) {
      db
          .update(
            'runtime_locks',
            {
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 2))
                  .toIso8601String(),
            },
            where: 'name = ? AND owner = ?',
            whereArgs: ['reminder_schedule', owner],
          )
          .catchError((_) => 0);
    });
    try {
      await NotificationLedger.consumeNativeEvents();
      if (!await NotificationService.pushEnabled()) {
        await NotificationService.cancelAll();
        return;
      }
      final plan = await _buildSchedulePlan();
      final desired = plan.map((p) => p.occurrence.notificationId).toSet();
      final native = await NativeNotificationBridge.records('pending');
      if (native != null) {
        // Only pending legacy requests are retired; visible old notifications stay.
        await NotificationService.retireLegacyPending();
        for (final row in native.where((r) => r['kind'] == 'snooze')) {
          await NotificationLedger.rememberSchedule(
            id: row['id'] as int,
            title: row['title'] as String,
            body: row['body'] as String,
            at: DateTime.fromMillisecondsSinceEpoch(
              row['at'] as int,
              isUtc: true,
            ),
            payload: row['payload'] as String?,
            kind: 'snooze',
          );
        }
      }
      final pending = (await NotificationService.getPending())
          .map((p) => p.id)
          .toSet();
      final registry = await db.query('scheduled_notifications');
      final registryById = {
        for (final row in registry) row['notification_id'] as int: row,
      };
      // Publish additions before retiring obsolete future instances. On failure
      // existing schedules remain available and a retry is idempotent.
      for (final planned in plan) {
        final occurrence = planned.occurrence;
        final payload = 'occurrenceId:${planned.occurrenceId}';
        final fingerprint = NotificationLedger.fingerprint(
          title: occurrence.title,
          body: occurrence.body,
          at: occurrence.scheduledTime,
          payload: payload,
        );
        final previous = registryById[occurrence.notificationId];
        if (!pending.contains(occurrence.notificationId) ||
            previous?['fingerprint'] != fingerprint) {
          await NotificationService.schedule(
            id: occurrence.notificationId,
            title: occurrence.title,
            body: occurrence.body,
            scheduledTime: occurrence.scheduledTime,
            payload: payload,
          );
        }
        await LocalReminderService.createScheduledLog(
          configId: planned.config.id,
          partnerId: planned.config.partnerId,
          message: occurrence.body,
          scheduledTime: occurrence.scheduledTime,
          occurrenceId: planned.occurrenceId,
        );
      }
      for (final row in registry) {
        final id = row['notification_id'] as int;
        final record = await ReminderOccurrenceService.getById(
          row['occurrence_id'] as String,
        );
        final enabled = record == null
            ? const []
            : await db.query(
                'reminder_configs',
                columns: ['id'],
                where:
                    "id = ? AND enabled = 1 AND (subject_kind = 'user' OR "
                    "EXISTS (SELECT 1 FROM partners p WHERE p.id = partner_id AND p.status = 'active'))",
                whereArgs: [record.configId],
              );
        final future = DateTime.parse(
          row['scheduled_for'] as String,
        ).isAfter(now);
        final keepSnooze =
            row['kind'] == 'snooze' &&
            record?.status == 'snoozed' &&
            enabled.isNotEmpty;
        if (keepSnooze && future && !pending.contains(id)) {
          final spec =
              jsonDecode(row['fingerprint'] as String) as Map<String, dynamic>;
          await NotificationService.schedule(
            id: id,
            title: spec['title'] as String,
            body: spec['body'] as String,
            payload: spec['payload'] as String?,
            kind: 'snooze',
            scheduledTime: tz.TZDateTime.from(
              DateTime.parse(row['scheduled_for'] as String),
              tz.local,
            ),
          );
        } else if (enabled.isEmpty ||
            (future && !desired.contains(id) && !keepSnooze)) {
          await NotificationService.cancel(id);
          if (record != null) {
            await db.update(
              'reminder_occurrences',
              {'status': 'cancelled', 'updated_at': now.toIso8601String()},
              where: "id = ? AND status IN ('scheduled', 'snoozed')",
              whereArgs: [record.id],
            );
          }
        }
      }
      // System evidence may arrive during scheduling; ingest once more.
      await NotificationLedger.consumeNativeEvents();
    } catch (error) {
      await NotificationLedger.record(
        'reconcile_failed',
        detail: error.runtimeType.toString(),
      );
      rethrow;
    } finally {
      renewal.cancel();
      await db.delete(
        'runtime_locks',
        where: 'name = ? AND owner = ?',
        whereArgs: ['reminder_schedule', owner],
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
      if (!config.isValid) continue;
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
        if (const {
          'acknowledged',
          'dismissed',
          'snoozed',
        }.contains(record.status)) {
          continue;
        }
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
