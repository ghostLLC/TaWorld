/// TaWorld 本地通知服务
///
/// 使用 flutter_local_notifications 替代 FCM 推送。
/// 支持即时通知和精确定时通知（zonedSchedule）。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

abstract final class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// 全局 GoRouter 引用，用于通知点击跳转
  static GoRouter? router;

  /// 初始化通知插件
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _initialized = true;
  }

  /// 请求通知权限（Android 13+）
  static Future<bool> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
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
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
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
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'taworld_reminders',
      'Ta的提醒',
      channelDescription: 'TaWorld 关怀提醒通知',
      importance: Importance.high,
      priority: Priority.high,
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
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }

  /// 定时通知（用于睡觉/吃饭/天气提醒）
  ///
  /// 使用 zonedSchedule 精确定时，底层依赖 Android AlarmManager。
  /// [scheduledTime] 为本地时间，内部自动转换为 TZDateTime。
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    // 如果调度时间已过，跳过
    if (scheduledTime.isBefore(DateTime.now())) return;

    const androidDetails = AndroidNotificationDetails(
      'taworld_reminders',
      'Ta的提醒',
      channelDescription: 'TaWorld 关怀提醒通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// 取消指定通知
  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// 取消所有通知
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// 获取当前待发送的调度通知数量
  static Future<List<PendingNotificationRequest>> getPending() async {
    return _plugin.pendingNotificationRequests();
  }

  /// 通知点击回调 — 跳转到对应页面
  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || router == null) return;

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
}
