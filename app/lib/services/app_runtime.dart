import 'dart:async';
import 'dart:developer' as dev;
import 'package:workmanager/workmanager.dart';
import 'background_tasks.dart';
import 'local/partner_service.dart';
import 'native_notification_bridge.dart';
import 'notification_service.dart';
import 'notification_ledger.dart';
import 'reminder_health_service.dart';
import 'reminder_scheduler.dart';
import 'timezone_service.dart';

/// Optional services start after the first frame and fail independently.
abstract final class AppRuntime {
  static Future<void>? _starting;
  static DateTime? _lastResume;
  static Future<void> start() => _starting ??= _start();
  static Future<void> _step(String name, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      dev.log('$name: ${error.runtimeType}', name: 'TaWorld');
    }
  }

  static Future<void> _start() async {
    await _step('时区初始化', () async {
      await TimezoneService.initialize();
    });
    await _step('通知初始化', NotificationService.init);
    await _step('读取提醒记录', NotificationLedger.consumeNativeEvents);
    await _step('恢复未来提醒', () async {
      await NativeNotificationBridge.invoke<bool>('restore');
    });
    await _step('后台任务初始化', () async {
      await Workmanager().initialize(callbackDispatcher);
      await BackgroundTaskService.registerAll();
    });
    PartnerService.refreshCounter.addListener(_dataChanged);
    await resume(force: true);
    await _step('通知打开位置', NotificationService.consumeLaunch);
  }

  static void _dataChanged() => unawaited(resume(force: true));
  static Future<void> resume({bool force = false}) async {
    if (!NotificationService.isInitialized) return;
    final now = DateTime.now();
    if (!force &&
        _lastResume != null &&
        now.difference(_lastResume!) < const Duration(seconds: 15)) {
      return;
    }
    _lastResume = now;
    await _step('更新设备时区', () async {
      await TimezoneService.initialize();
    });
    await _step('核对提醒计划', ReminderScheduler.scheduleAll);
    await ReminderHealthService.check();
  }
}
