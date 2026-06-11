/// TaWorld 本地通知服务
///
/// 使用 flutter_local_notifications 替代 FCM 推送。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract final class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

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
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
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

  /// 定时通知（用于睡觉/吃饭提醒）
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    // 使用 android_alarm_manager 或 workmanager 做精确定时
    // 这里简化为立即发送（精确定时由 WorkManager 任务调度实现）
    await show(id: id, title: title, body: body, payload: payload);
  }

  /// 通知点击回调
  static void _onNotificationTap(NotificationResponse response) {
    // 可以根据 payload 跳转到对应页面
    // 后续通过全局事件或路由参数实现
  }
}
