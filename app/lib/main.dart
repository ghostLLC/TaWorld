import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'services/background_tasks.dart';
import 'services/notification_service.dart';
import 'services/reminder_scheduler.dart';
import 'services/timezone_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var timezoneInitialized = false;
  try {
    await TimezoneService.initialize();
    timezoneInitialized = true;
  } catch (error, stackTrace) {
    dev.log(
      '时区初始化失败，跳过启动提醒调度: $error',
      name: 'TaWorld',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    // 初始化通知插件
    await NotificationService.init();

    // 请求通知权限（Android 13+）
    await NotificationService.requestPermission();

    // 初始化 WorkManager 后台任务
    await Workmanager().initialize(callbackDispatcher);
    await BackgroundTaskService.registerAll();

    // 调度所有启用的提醒通知。时区失败时保留既有通知，等待后续重试。
    if (timezoneInitialized) {
      await ReminderScheduler.scheduleAll();
    }
  } catch (error, stackTrace) {
    dev.log(
      '通知或后台服务初始化失败: $error',
      name: 'TaWorld',
      error: error,
      stackTrace: stackTrace,
    );
  }

  runApp(const TaWorldApp());
}
