import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'services/background_tasks.dart';
import 'services/notification_service.dart';
import 'services/reminder_scheduler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化时区数据（zonedSchedule 依赖）
  tz_data.initializeTimeZones();

  // 初始化通知插件
  await NotificationService.init();

  // 请求通知权限（Android 13+）
  await NotificationService.requestPermission();

  // 初始化 WorkManager 后台任务
  await Workmanager().initialize(callbackDispatcher);
  await BackgroundTaskService.registerAll();

  // 调度所有启用的提醒通知
  await ReminderScheduler.scheduleAll();

  runApp(TaWorldApp());
}
