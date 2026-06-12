/// TaWorld — 应用入口
///
/// MaterialApp 配置，整合主题、路由。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_scheduler.dart';

/// TaWorld 应用根组件
class TaWorldApp extends StatefulWidget {
  const TaWorldApp({super.key});

  @override
  State<TaWorldApp> createState() => _TaWorldAppState();

  /// 全局 router 引用，供通知点击回调使用
  static final GoRouter router = createRouter();
}

class _TaWorldAppState extends State<TaWorldApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    ThemeService.instance.addListener(_onThemeChanged);
    ThemeService.instance.init();

    // 将 router 引用传递给 NotificationService，用于通知点击跳转
    NotificationService.router = TaWorldApp.router;

    // 监听 App 生命周期，恢复前台时续期通知调度
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    ThemeService.instance.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App 恢复前台时，重新调度未来 7 天的通知
      ReminderScheduler.scheduleAll();
    }
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ta的世界',
      debugShowCheckedModeBanner: false,

      // 主题
      theme: TaTheme.light,
      darkTheme: TaTheme.dark,
      themeMode: ThemeService.instance.mode,

      // 路由
      routerConfig: TaWorldApp.router,
    );
  }
}
