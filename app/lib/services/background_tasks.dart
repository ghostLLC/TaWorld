/// TaWorld 后台任务服务
///
/// 使用 WorkManager 实现后台周期性任务：
/// - 天气轮询：约每 30 分钟检查突变监测配置的逐时预报
/// - 通知续期：每次后台执行时补充 zonedSchedule 通知（防止 7 天窗口过期）
///
/// 注意：回调函数运行在独立 Isolate 中，不能使用任何 UI 相关代码。
library;

import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../services/local/local_reminder_service.dart';
import '../services/local/partner_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_scheduler.dart';
import '../services/weather_service.dart';
import '../services/weather_background_processor.dart';
import '../services/ai_proactive_service.dart';
import '../services/ai_memory_dreamer.dart';
import '../services/timezone_service.dart';

/// 后台任务名称常量
const _taskWeatherCheck = 'taworld_weather_check';
const _taskNotificationRenew = 'taworld_notification_renew';
const _taskAiProactiveCheck = 'taworld_ai_proactive_check';
const _taskAiMemoryDream = 'taworld_ai_memory_dream';

/// 后台任务初始化
abstract final class BackgroundTaskService {
  /// 注册所有周期性后台任务
  static Future<void> registerAll() async {
    await Workmanager().cancelAll();

    // 天气突变轮询：WorkManager 只保证“尽力执行”，Doze / 厂商省电
    // 可能延迟任务，30 分钟不是实时送达承诺。
    await Workmanager().registerPeriodicTask(
      _taskWeatherCheck,
      _taskWeatherCheck,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );

    // 通知续期：每 12 小时执行，确保 zonedSchedule 不超 7 天窗口
    await Workmanager().registerPeriodicTask(
      _taskNotificationRenew,
      _taskNotificationRenew,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );

    // AI 主动评估：每 2 小时检查是否需要主动发消息
    await Workmanager().registerPeriodicTask(
      _taskAiProactiveCheck,
      _taskAiProactiveCheck,
      frequency: const Duration(hours: 2),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );

    // AI 记忆整合（Dreaming）：每天执行一次，整合、去重、衰减记忆
    await Workmanager().registerPeriodicTask(
      _taskAiMemoryDream,
      _taskAiMemoryDream,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
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
    dev.log('后台任务开始: $taskName', name: 'TaWorld');

    try {
      // 后台 Isolate 的静态变量为空，必须在任务内初始化设备时区。
      await TimezoneService.initialize();

      switch (taskName) {
        case _taskWeatherCheck:
          await _runWeatherCheck();
        case _taskNotificationRenew:
          await _runNotificationRenew();
        case _taskAiProactiveCheck:
          await _runAiProactiveCheck();
        case _taskAiMemoryDream:
          await _runAiMemoryDream();
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

/// 检查所有关注人所在地的逐时预报，发现配置的天气突变后推送。
///
/// 这是设备端 best-effort 监测：系统省电、网络和后台限制都可能造成延迟。
Future<void> _runWeatherCheck() async {
  final partners = await PartnerService.getAll();
  if (partners.isEmpty) return;

  final configsByPartner = await LocalReminderService.getAllEnabledConfigs();
  final prefs = await SharedPreferences.getInstance();
  final nowUtc = DateTime.now().toUtc();

  // 初始化后台通知插件
  final bgPlugin = FlutterLocalNotificationsPlugin();
  await bgPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final stateStore = _PreferencesWeatherAlertStateStore(prefs);
  final alertSink = _PluginWeatherAlertSink(bgPlugin);

  for (final partner in partners) {
    final configs =
        configsByPartner[partner.id]
            ?.where(
              (config) =>
                  config.category == 'weather' &&
                  config.config['mode'] == 'weather_change',
            )
            .toList() ??
        const [];
    FullWeatherResult? weather;
    if (partner.latitude != null && partner.longitude != null) {
      weather = await WeatherService.getFullWeatherByCoords(
        partner.latitude!,
        partner.longitude!,
      );
    } else if (partner.city != null && partner.city!.isNotEmpty) {
      weather = await WeatherService.getFullWeather(partner.city!);
    }
    if (weather == null) continue;

    // 每轮都刷新所有人物的天气缓存；只有显式开启突变监测的配置
    // 才会继续产生通知，避免无授权的打扰。
    await WeatherBackgroundProcessor.processPartner(
      partner: partner,
      configs: configs,
      weather: weather,
      nowUtc: nowUtc,
      deviceTimeZoneId: tz.local.name,
      stateStore: stateStore,
      alertSink: alertSink,
    );
  }
}

class _PreferencesWeatherAlertStateStore implements WeatherAlertStateStore {
  const _PreferencesWeatherAlertStateStore(this.preferences);

  final SharedPreferences preferences;

  @override
  Future<WeatherAlertState?> read(String configId) async {
    final eventKey = preferences.getString('weather_alert_event_$configId');
    final timestamp = preferences.getInt('weather_alert_time_$configId');
    if (eventKey == null || timestamp == null) return null;
    return WeatherAlertState(
      eventKey: eventKey,
      notifiedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      ),
    );
  }

  @override
  Future<void> write(String configId, WeatherAlertState state) async {
    await preferences.setString(
      'weather_alert_event_$configId',
      state.eventKey,
    );
    await preferences.setInt(
      'weather_alert_time_$configId',
      state.notifiedAtUtc.toUtc().millisecondsSinceEpoch,
    );
  }
}

class _PluginWeatherAlertSink implements WeatherAlertSink {
  const _PluginWeatherAlertSink(this.plugin);

  final FlutterLocalNotificationsPlugin plugin;

  @override
  Future<void> show(WeatherAlertDelivery delivery) async {
    var notificationId = delivery.event.eventKey.hashCode & 0x7fffffff;
    if (notificationId == 0) notificationId = 1;
    await plugin.show(
      notificationId,
      '天气变化提醒',
      delivery.event.message,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'taworld_weather_alert',
          '天气变化提醒',
          channelDescription: 'TaWorld 对未来天气变化的尽力监测提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'configId:${delivery.configId}',
    );
  }
}

// ==================== 通知续期任务 ====================

/// 补充调度 zonedSchedule 通知，防止 7 天窗口过期后通知断档
Future<void> _runNotificationRenew() async {
  await NotificationService.init();
  await ReminderScheduler.scheduleAll();
  dev.log('通知续期完成', name: 'TaWorld');
}

// ==================== AI 主动评估任务 ====================

/// 后台 AI 主动评估：收集上下文 → AI 判断 → 生成待发消息 + 通知
Future<void> _runAiProactiveCheck() async {
  try {
    final sent = await AiProactiveService.evaluate();
    dev.log('AI 主动评估完成，是否发送: $sent', name: 'TaWorld');
  } catch (e) {
    dev.log('AI 主动评估失败: $e', name: 'TaWorld');
  }
}

// ==================== AI 记忆整合（Dreaming）任务 ====================

/// 后台记忆整合：衰减、去重、合并、摘要历史对话
Future<void> _runAiMemoryDream() async {
  try {
    final result = await AiMemoryDreamer.dream();
    dev.log(
      'AI Dreaming 完成: 衰减=${result.decayed}, 归档=${result.archived}, '
      '合并=${result.merged}, 摘要=${result.summarized}',
      name: 'TaWorld',
    );
  } catch (e) {
    dev.log('AI Dreaming 失败: $e', name: 'TaWorld');
  }
}
