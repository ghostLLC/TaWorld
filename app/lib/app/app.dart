/// TaWorld — 应用入口
///
/// MaterialApp 配置，整合主题、路由。
library;

import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';
import '../services/theme_service.dart';

/// TaWorld 应用根组件
class TaWorldApp extends StatefulWidget {
  const TaWorldApp({super.key});

  @override
  State<TaWorldApp> createState() => _TaWorldAppState();
}

class _TaWorldAppState extends State<TaWorldApp> {
  @override
  void initState() {
    super.initState();
    ThemeService.instance.addListener(_onThemeChanged);
    ThemeService.instance.init();
  }

  @override
  void dispose() {
    ThemeService.instance.removeListener(_onThemeChanged);
    super.dispose();
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
      routerConfig: createRouter(),
    );
  }
}
