/// TaWorld 本地通知服务
///
/// 使用 flutter_local_notifications 替代 FCM 推送。
/// 支持即时通知和精确定时通知（zonedSchedule）。
library;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/database_helper.dart';
import 'native_notification_bridge.dart';
import 'notification_ledger.dart';
import 'notification_identity.dart';
import 'timezone_service.dart';
import 'local/partner_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_occurrence_service.dart';

enum ReminderNotificationAction {
  done('reminder_done'),
  snooze('reminder_snooze_5'),
  outdated('reminder_outdated');

  const ReminderNotificationAction(this.id);

  final String id;

  static ReminderNotificationAction? fromId(String? id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  await TimezoneService.initialize();
  await NotificationService.init();
  await NotificationService.handleResponse(response, allowNavigation: false);
}

abstract final class NotificationSchedulePolicy {
  static AndroidScheduleMode modeFor({required bool? canScheduleExact}) {
    return canScheduleExact == true
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }
}

abstract final class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _queuedPayload;

  static bool get isInitialized => _initialized;

  /// 全局 GoRouter 引用，用于通知点击跳转
  static GoRouter? router;

  /// 初始化通知插件
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    NativeNotificationBridge.channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationOpened' && call.arguments is String) {
        _queuedPayload = call.arguments as String;
        if (router != null) await consumeLaunch();
      }
    });
    _initialized = true;
  }

  static Future<bool> pushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool('push_enabled') ?? true;
  }

  static Future<void> consumeLaunch() async {
    if (router == null) return;
    final native = await NativeNotificationBridge.invoke<String>(
      'launchPayload',
    );
    final payload = _queuedPayload ?? native;
    _queuedPayload = null;
    if (payload != null && payload.isNotEmpty) {
      await handleResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: payload,
        ),
      );
    } else {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse != null) {
        await handleResponse(launch!.notificationResponse!);
      }
    }
  }

  /// 请求通知权限（Android 13+）
  static Future<bool> requestPermission() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      // 请求通知权限
      final granted = await androidPlugin.requestNotificationsPermission();
      // 同时请求精确定时权限（Android 14+）
      final canSchedule = await androidPlugin.canScheduleExactNotifications();
      if (canSchedule == false) {
        await androidPlugin.requestExactAlarmsPermission();
      }
      return granted ?? false;
    }
    return true;
  }

  /// 检查通知权限状态
  ///
  /// 返回 (通知是否开启, 精确定时是否允许)
  static Future<(bool, bool)> checkPermission() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return (true, true);

    final enabled = await androidPlugin.areNotificationsEnabled() ?? false;
    final canSchedule =
        await androidPlugin.canScheduleExactNotifications() ?? false;
    return (enabled, canSchedule);
  }

  /// 发送即时通知
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'taworld_reminders',
    String channelName = 'Ta的提醒',
  }) async {
    if (!await pushEnabled()) throw StateError('通知已关闭');
    final native = await NativeNotificationBridge.invoke<bool>('show', {
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'at': DateTime.now().millisecondsSinceEpoch,
      'channel': channelId,
      'channelName': channelName,
    });
    if (native != null) {
      if (!native) throw StateError('系统未接受通知，请检查通知设置');
      return;
    }
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'TaWorld 关怀提醒通知',
      importance: Importance.high,
      priority: Priority.high,
      actions: _reminderActions,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  /// 定时通知（用于睡觉/吃饭/天气提醒）
  ///
  /// 使用 zonedSchedule 精确定时，底层依赖 Android AlarmManager。
  /// [scheduledTime] 已经包含要使用的 IANA 时区位置。
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    String? payload,
    String kind = 'regular',
  }) async {
    // 如果调度时间已过，跳过
    if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) {
      throw StateError('提醒时间已经过去');
    }
    if (!await pushEnabled()) throw StateError('通知已关闭');
    final native = await NativeNotificationBridge.invoke<bool>('schedule', {
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'at': scheduledTime.millisecondsSinceEpoch,
      'kind': kind,
    });
    if (native == true) {
      await NotificationLedger.rememberSchedule(
        id: id,
        title: title,
        body: body,
        at: scheduledTime,
        payload: payload,
        kind: kind,
      );
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'taworld_reminders',
      'Ta的提醒',
      channelDescription: 'TaWorld 关怀提醒通知',
      importance: Importance.high,
      priority: Priority.high,
      actions: _reminderActions,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final canScheduleExact = await androidPlugin
        ?.canScheduleExactNotifications();

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTime,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: NotificationSchedulePolicy.modeFor(
        canScheduleExact: canScheduleExact,
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
    await NotificationLedger.rememberSchedule(
      id: id,
      title: title,
      body: body,
      at: scheduledTime,
      payload: payload,
      kind: kind,
    );
  }

  /// Canceling one future request does not clear unrelated visible notifications.
  /// 取消指定通知
  static Future<void> cancel(int id) async {
    await NativeNotificationBridge.invoke<bool>('cancel', id);
    await _plugin.cancel(id);
    final db = await DatabaseHelper.database;
    await db.delete(
      'scheduled_notifications',
      where: 'notification_id = ?',
      whereArgs: [id],
    );
  }

  /// 取消所有通知
  static Future<void> cancelAll() async {
    await NativeNotificationBridge.invoke<bool>('cancelAll');
    await _plugin.cancelAll();
    final db = await DatabaseHelper.database;
    await db.delete('scheduled_notifications');
  }

  static Future<void> retireLegacyPending() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      await _plugin.cancel(request.id);
    }
  }

  /// 获取当前待发送的调度通知数量
  static Future<List<PendingNotificationRequest>> getPending() async {
    final native = await NativeNotificationBridge.records('pending');
    final legacy = await _plugin.pendingNotificationRequests();
    return [
      ...legacy,
      if (native != null)
        ...native.map(
          (row) => PendingNotificationRequest(
            row['id'] as int,
            row['title'] as String?,
            row['body'] as String?,
            row['payload'] as String?,
          ),
        ),
    ];
  }

  /// 通知点击回调 — 跳转到对应页面
  static const _reminderActions = <AndroidNotificationAction>[
    AndroidNotificationAction('reminder_done', '关心过了'),
    AndroidNotificationAction('reminder_snooze_5', '5分钟后'),
    AndroidNotificationAction('reminder_outdated', '过时了'),
  ];

  static void _onNotificationTap(NotificationResponse response) {
    handleResponse(response);
  }

  static Future<void> handleResponse(
    NotificationResponse response, {
    bool allowNavigation = true,
  }) async {
    final payload = response.payload;
    if (payload == null) return;

    if (payload.startsWith('occurrenceId:')) {
      final occurrenceId = payload.substring('occurrenceId:'.length);
      final action = ReminderNotificationAction.fromId(response.actionId);
      if (action != null) {
        await respondToOccurrence(occurrenceId, action);
        return;
      }
      if (allowNavigation && router != null) {
        final record = await ReminderOccurrenceService.getById(occurrenceId);
        final person = record?.subjectKind == 'partner'
            ? await PartnerService.getById(record!.subjectId)
            : null;
        router!.go(
          person?.status == 'active' ? '/partners/${record!.subjectId}' : '/',
        );
      } else if (allowNavigation) {
        _queuedPayload = payload;
      }
      return;
    }

    if (!allowNavigation || router == null) return;

    // payload 格式: "configId:xxx" 或 "logId:xxx" 或纯路由路径
    if (payload.startsWith('/')) {
      router!.go(payload);
    } else if (payload.startsWith('configId:')) {
      final id = payload.substring('configId:'.length);
      router!.go('/reminders/$id/logs');
    } else if (payload.startsWith('logId:')) {
      // 回到首页（关怀概览）
      router!.go('/');
    } else {
      // 兜底：未知格式跳首页
      router!.go('/');
    }
  }

  static Future<void> respondToOccurrence(
    String occurrenceId,
    ReminderNotificationAction action,
  ) async {
    final current = await ReminderOccurrenceService.getById(occurrenceId);
    if (current == null) return;
    final configs = await (await DatabaseHelper.database).query(
      'reminder_configs',
      where: 'id = ? AND enabled = 1',
      whereArgs: [current.configId],
    );
    if (configs.isEmpty) return;
    final userResponse = switch (action) {
      ReminderNotificationAction.done => ReminderUserResponse.done,
      ReminderNotificationAction.snooze => ReminderUserResponse.snooze,
      ReminderNotificationAction.outdated => ReminderUserResponse.outdated,
    };
    final updated = await ReminderOccurrenceService.respond(
      occurrenceId,
      userResponse,
    );
    if (updated.response != userResponse.wireName) return;
    final known = await (await DatabaseHelper.database).query(
      'scheduled_notifications',
      where: 'occurrence_id = ?',
      whereArgs: [occurrenceId],
    );
    for (final row in known) {
      await cancel(row['notification_id'] as int);
    }
    await NotificationLedger.record(
      'action_${userResponse.wireName}',
      occurrenceId: occurrenceId,
      detail: action == ReminderNotificationAction.snooze
          ? updated.snoozedUntil!.millisecondsSinceEpoch.toString()
          : null,
    );
    if (action != ReminderNotificationAction.snooze) return;

    final time = tz.TZDateTime.from(updated.snoozedUntil!, tz.local);
    await schedule(
      id: notificationIdFor('snooze:$occurrenceId'),
      kind: 'snooze',
      title: '稍后再提醒你',
      body: updated.message ?? '刚才的提醒可以继续处理了',
      scheduledTime: time,
      payload: 'occurrenceId:$occurrenceId',
    );
  }

  static Future<void> cancelForConfig(String configId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.rawQuery(
      'SELECT s.notification_id FROM scheduled_notifications s '
      'JOIN reminder_occurrences r ON r.id = s.occurrence_id WHERE r.config_id = ?',
      [configId],
    );
    for (final row in rows) {
      await cancel(row['notification_id'] as int);
    }
  }
}
