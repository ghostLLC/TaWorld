import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import '../data/local/database_helper.dart';
import 'local/local_reminder_service.dart';
import 'local/partner_service.dart';
import 'native_notification_bridge.dart';
import 'notification_ledger.dart';
import 'notification_service.dart';
import 'reminder_scheduler.dart';

class ReminderHealth {
  const ReminderHealth({
    required this.checkedAt,
    required this.pushEnabled,
    required this.notificationAllowed,
    required this.exactAllowed,
    required this.channelAllowed,
    required this.configCount,
    required this.pendingCount,
    required this.observedCount,
    required this.acknowledgedCount,
    required this.unknownCount,
    required this.issues,
    this.nextAt,
    this.error,
    this.lastBackgroundOutcome,
  });
  final DateTime checkedAt;
  final bool pushEnabled, notificationAllowed, exactAllowed, channelAllowed;
  final int configCount,
      pendingCount,
      observedCount,
      acknowledgedCount,
      unknownCount;
  final List<String> issues;
  final DateTime? nextAt;
  final String? error, lastBackgroundOutcome;
  bool get hasIssue => issues.isNotEmpty || error != null;
  String get summary {
    if (error != null) return '提醒检查暂未完成';
    if (!pushEnabled) return '提醒通知已暂停';
    if (issues.isNotEmpty) return issues.first;
    if (unknownCount > 0) return '$unknownCount 条历史提醒无法确认是否显示';
    if (nextAt != null) return '下一次提醒 ${formatTime(nextAt!)}';
    return configCount == 0 ? '还没有设置提醒' : '提醒检查已完成';
  }

  static String formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

abstract final class ReminderHealthService {
  static final current = ValueNotifier<ReminderHealth?>(null);
  static Future<void>? _inFlight;
  static Future<void> check({bool repair = false}) {
    if (_inFlight != null) return _inFlight!;
    return _inFlight = _check(
      repair: repair,
    ).whenComplete(() => _inFlight = null);
  }

  static Future<void> _check({required bool repair}) async {
    final now = DateTime.now();
    try {
      if (repair) await ReminderScheduler.scheduleAll();
      await NotificationLedger.consumeNativeEvents();
      final permissions = await NotificationService.checkPermission();
      final push = await NotificationService.pushEnabled();
      final channel =
          await NativeNotificationBridge.invoke<bool>('channelAllowed') ??
          permissions.$1;
      final configs = await LocalReminderService.getAllEnabledConfigList();
      final people = {for (final p in await PartnerService.getAll()) p.id: p};
      final pending = await NotificationService.getPending();
      final pendingIds = pending.map((p) => p.id).toSet();
      final db = await DatabaseHelper.database;
      final stored = await db.query('reminder_occurrences');
      final finished = {
        for (final row in stored)
          if (const {
            'acknowledged',
            'dismissed',
            'snoozed',
          }.contains(row['status']))
            '${row['config_id']}|${row['scheduled_for']}',
      };
      final issues = <String>[];
      DateTime? next;
      final enabledIds = configs.map((c) => c.id).toSet();
      for (final row in stored) {
        if (row['status'] != 'snoozed' ||
            !enabledIds.contains(row['config_id'])) {
          continue;
        }
        final until = DateTime.tryParse(row['snoozed_until'] as String? ?? '');
        if (until != null &&
            until.isAfter(now) &&
            (next == null || until.isBefore(next))) {
          next = until;
        }
      }
      var missing = 0;
      for (final config in configs) {
        final person = people[config.partnerId];
        final name = config.isSelfReminder ? '自己' : person?.nickname ?? '这位好友';
        if (!config.isValid) {
          issues.add('$name的提醒配置需要修复');
          continue;
        }
        if (config.category == 'weather' &&
            config.config['mode'] == 'weather_change') {
          continue;
        }
        if (!config.isSelfReminder && person == null) continue;
        final occurrences = config.isSelfReminder
            ? ReminderScheduler.calculateSelfOccurrences(
                config: config,
                now: tz.TZDateTime.now(tz.local),
              )
            : ReminderScheduler.calculateOccurrences(
                config: config,
                partner: person!,
                now: tz.TZDateTime.now(tz.local),
              );
        if (occurrences.isEmpty) {
          final once = config.config['scheduled_at'];
          if (once is String &&
              DateTime.tryParse(once)?.isBefore(now) == true) {
            continue;
          }
          issues.add('$name的提醒缺少有效时间或地点');
          continue;
        }
        for (final occurrence in occurrences) {
          if (finished.contains(
            '${config.id}|${occurrence.scheduledTime.toUtc().toIso8601String()}',
          )) {
            continue;
          }
          if (next == null || occurrence.scheduledTime.isBefore(next)) {
            next = occurrence.scheduledTime;
          }
          if (!pendingIds.contains(occurrence.notificationId)) missing++;
        }
      }
      if (configs.isNotEmpty && push) {
        if (!permissions.$1) {
          issues.insert(0, '手机通知权限未开启');
        } else if (!channel) {
          issues.insert(0, '提醒通知渠道已关闭');
        }
        if (!permissions.$2) issues.add('精确定时未开启，提醒时间可能延后');
        if (missing > 0) issues.add('$missing 次未来提醒需要重新排程');
      }
      final recent = await db.query(
        'reminder_occurrences',
        where: 'scheduled_for >= ? AND scheduled_for <= ?',
        whereArgs: [
          now.subtract(const Duration(days: 1)).toUtc().toIso8601String(),
          now.toUtc().toIso8601String(),
        ],
      );
      final background = await db.query(
        'background_runs',
        where: 'task = ?',
        whereArgs: ['ai_proactive_evaluation'],
        orderBy: 'started_at DESC',
        limit: 1,
      );
      current.value = ReminderHealth(
        checkedAt: now,
        pushEnabled: push,
        notificationAllowed: permissions.$1,
        exactAllowed: permissions.$2,
        channelAllowed: channel,
        configCount: configs.length,
        pendingCount: pending.length,
        nextAt: next,
        observedCount: recent.where((r) => r['delivered_at'] != null).length,
        acknowledgedCount: recent
            .where((r) => r['status'] == 'acknowledged')
            .length,
        unknownCount: recent
            .where(
              (r) =>
                  const {
                    'scheduled',
                    'posted',
                    'unknown',
                  }.contains(r['status']) &&
                  r['delivered_at'] == null,
            )
            .length,
        issues: issues.toSet().toList(),
        lastBackgroundOutcome: background.isEmpty
            ? null
            : background.first['outcome'] as String?,
      );
    } catch (_) {
      current.value = ReminderHealth(
        checkedAt: now,
        pushEnabled: true,
        notificationAllowed: false,
        exactAllowed: false,
        channelAllowed: false,
        configCount: 0,
        pendingCount: 0,
        observedCount: 0,
        acknowledgedCount: 0,
        unknownCount: 0,
        issues: const [],
        error: '检查暂未完成，请稍后重试；这不代表提醒已经失败。',
      );
    }
  }
}
