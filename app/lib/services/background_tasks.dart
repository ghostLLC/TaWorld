/// TaWorld 后台任务服务
///
/// 使用 WorkManager 实现后台周期性任务：
/// - 天气轮询：每 2 小时检查所有关注人所在地天气，发现极端天气主动推送
/// - 通知续期：每次后台执行时补充 zonedSchedule 通知（防止 7 天窗口过期）
///
/// 注意：回调函数运行在独立 Isolate 中，不能使用任何 UI 相关代码。
library;

import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:workmanager/workmanager.dart';

import '../services/local/local_reminder_service.dart';
import '../services/local/partner_service.dart';
import '../services/reminder_scheduler.dart';
import '../services/weather_service.dart';

/// 后台任务名称常量
const _taskWeatherCheck = 'taworld_weather_check';
const _taskNotificationRenew = 'taworld_notification_renew';

/// 后台任务初始化
abstract final class BackgroundTaskService {
  /// 注册所有周期性后台任务
  static Future<void> registerAll() async {
    await Workmanager().cancelAll();

    // 天气轮询：每 2 小时执行一次（Android 最小 15 分钟）
    await Workmanager().registerPeriodicTask(
      _taskWeatherCheck,
      _taskWeatherCheck,
      frequency: const Duration(hours: 2),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );

    // 通知续期：每 12 小时执行，确保 zonedSchedule 不超 7 天窗口
    await Workmanager().registerPeriodicTask(
      _taskNotificationRenew,
      _taskNotificationRenew,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// 取消所有后台任务
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}

// ==================== 回调入口 ====================

/// WorkManager 回调调度器 — 必须是顶层函数
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // 初始化时区数据（后台 Isolate 中静态变量为空）
    tz_data.initializeTimeZones();

    dev.log('后台任务开始: $taskName', name: 'TaWorld');

    try {
      switch (taskName) {
        case _taskWeatherCheck:
          await _runWeatherCheck();
        case _taskNotificationRenew:
          await _runNotificationRenew();
        case Workmanager.iOSBackgroundTask:
          // iOS 后台任务（暂不处理）
          break;
      }
      dev.log('后台任务完成: $taskName', name: 'TaWorld');
      return true;
    } catch (e, st) {
      dev.log('后台任务失败: $taskName\n$e\n$st', name: 'TaWorld');
      return false;
    }
  });
}

// ==================== 天气轮询任务 ====================

/// 检查所有关注人所在地的天气，发现极端天气主动推送通知
Future<void> _runWeatherCheck() async {
  final partners = await PartnerService.getAll();
  if (partners.isEmpty) return;

  final configsByPartner = await LocalReminderService.getAllEnabledConfigs();
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();

  // 初始化后台通知插件
  final bgPlugin = FlutterLocalNotificationsPlugin();
  await bgPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  for (final partner in partners) {
    // 获取天气
    WeatherResult? weather;
    if (partner.latitude != null && partner.longitude != null) {
      weather = await WeatherService.getCurrentWeather(
        partner.longitude!,
        partner.latitude!,
      );
    } else if (partner.city != null && partner.city!.isNotEmpty) {
      weather = await WeatherService.getCurrentWeatherByCity(partner.city!);
    }
    if (weather == null) continue;

    // 检查天气条件
    final configs = configsByPartner[partner.id];
    if (configs == null) continue;

    for (final config in configs) {
      if (config.category != 'weather') continue;

      final conditions = (config.config['notify_conditions'] as List?)
              ?.cast<String>() ??
          ['rain', 'snow', 'extreme_cold', 'extreme_heat'];
      final check = WeatherService.checkConditions(weather, conditions);

      if (!check.shouldRemind || check.condition == null) continue;

      // 防重复：同一 partner + 同一条件类型，4 小时内不重复推送
      final dedupeKey =
          'bg_alert_${partner.id}_${check.condition}_${now.year}${now.month}${now.day}';
      final lastAlert = prefs.getInt('bg_alert_time_$dedupeKey');
      if (lastAlert != null) {
        final elapsed = now.difference(
          DateTime.fromMillisecondsSinceEpoch(lastAlert),
        );
        if (elapsed.inHours < 4) continue;
      }

      // 发送通知
      await bgPlugin.show(
        _makeAlertId(partner.id, check.condition!),
        '🚨 天气预警',
        check.message!,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'taworld_weather_alert',
            '天气预警',
            channelDescription: 'TaWorld 极端天气主动预警',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: 'configId:${config.id}',
      );

      // 记录推送时间
      await prefs.setInt(
        'bg_alert_time_$dedupeKey',
        now.millisecondsSinceEpoch,
      );
    }
  }
}

/// 生成唯一通知 ID
int _makeAlertId(String partnerId, String condition) {
  return '${partnerId}_$condition'.hashCode.abs() % 2147483647;
}

// ==================== 通知续期任务 ====================

/// 补充调度 zonedSchedule 通知，防止 7 天窗口过期后通知断档
Future<void> _runNotificationRenew() async {
  await ReminderScheduler.scheduleAll();
  dev.log('通知续期完成', name: 'TaWorld');
}
