/// TaWorld — 应用入口
///
/// MaterialApp 配置，整合主题、路由。
library;

import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

/// TaWorld 应用根组件
class TaWorldApp extends StatelessWidget {
  TaWorldApp({super.key});

  final _router = createRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ta的世界',
      debugShowCheckedModeBanner: false,

      // 主题
      theme: TaTheme.light,
      darkTheme: TaTheme.dark,
      themeMode: ThemeMode.system,

      // 路由
      routerConfig: _router,
    );
  }
}
