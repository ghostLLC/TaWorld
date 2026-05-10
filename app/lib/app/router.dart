/// TaWorld 路由配置
///
/// 使用 GoRouter 声明式路由。所有页面路径在此集中定义。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/screens/home/home_screen.dart';
import '../presentation/screens/login/login_screen.dart';
import '../services/auth_service.dart';

/// 路由路径常量
abstract final class Routes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const relationships = '/relationships';
  static const relationshipDetail = '/relationships/:id';
  static const reminderConfig = '/reminders/config/:relId';
  static const reminderHistory = '/reminders/:id/logs';
  static const achievements = '/achievements';
  static const aiChat = '/ai/chat';
  static const profile = '/profile';
  static const settings = '/settings';
}

/// 创建路由配置
GoRouter createRouter() {
  return GoRouter(
    initialLocation: Routes.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) async {
      final isLoggedIn = await AuthService.isLoggedIn();
      final isLoginRoute = state.matchedLocation == Routes.login ||
          state.matchedLocation == Routes.register;

      if (!isLoggedIn && !isLoginRoute) {
        return Routes.login;
      }
      if (isLoggedIn && state.matchedLocation == Routes.splash) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      // 登录
      GoRoute(
        path: Routes.login,
        builder: (_, __) => const LoginScreen(),
      ),

      // 注册（其他 AI 实现）
      GoRoute(
        path: Routes.register,
        builder: (_, __) => const _Placeholder(title: '注册'),
      ),

      // 首页（含底部导航）
      GoRoute(
        path: Routes.home,
        builder: (_, __) => const HomeScreen(),
      ),

      // === 以下页面由其他 AI 实现 ===

      GoRoute(
        path: Routes.relationships,
        builder: (_, __) => const _Placeholder(title: '关系管理'),
      ),

      GoRoute(
        path: Routes.relationshipDetail,
        builder: (context, state) => _Placeholder(
          title: '关系详情',
          subtitle: 'ID: ${state.pathParameters['id']}',
        ),
      ),

      GoRoute(
        path: Routes.reminderConfig,
        builder: (_, state) => _Placeholder(
          title: '提醒配置',
          subtitle: '关系: ${state.pathParameters['relId']}',
        ),
      ),

      GoRoute(
        path: Routes.reminderHistory,
        builder: (_, state) => _Placeholder(
          title: '提醒历史',
          subtitle: '配置: ${state.pathParameters['id']}',
        ),
      ),

      GoRoute(
        path: Routes.achievements,
        builder: (_, __) => const _Placeholder(title: '成就'),
      ),

      GoRoute(
        path: Routes.aiChat,
        builder: (_, __) => const _Placeholder(title: 'AI 助手'),
      ),

      GoRoute(
        path: Routes.profile,
        builder: (_, __) => const _Placeholder(title: '个人中心'),
      ),

      GoRoute(
        path: Routes.settings,
        builder: (_, __) => const _Placeholder(title: '设置'),
      ),
    ],
  );
}

/// 临时占位页面（其他 AI 替换为真实实现）
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('等待实现', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
