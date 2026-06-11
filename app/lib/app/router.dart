/// TaWorld 路由配置（单机版）
///
/// 使用 GoRouter 声明式路由。所有页面路径在此集中定义。
library;

import 'package:go_router/go_router.dart';

import '../presentation/screens/achievements/achievements_screen.dart';
import '../presentation/screens/ai_chat/ai_chat_screen.dart';
import '../presentation/screens/home/home_screen.dart';
import '../presentation/screens/add_partner/add_partner_screen.dart';
import '../presentation/screens/api_key_setup/api_key_setup_screen.dart';
import '../presentation/screens/reminder_config/reminder_config_screen.dart';
import '../presentation/screens/partner_detail/partner_detail_screen.dart';
import '../presentation/screens/reminder_history/reminder_history_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';

/// 路由路径常量
abstract final class Routes {
  static const home = '/';
  static const partnerDetail = '/partners/:id';
  static const addPartner = '/partners/add';
  static const reminderConfig = '/reminders/config/:partnerId';
  static const reminderHistory = '/reminders/:id/logs';
  static const achievements = '/achievements';
  static const aiChat = '/ai/chat';
  static const apiKeys = '/settings/api-keys';
  static const settings = '/settings';
}

/// 创建路由配置
GoRouter createRouter() {
  return GoRouter(
    initialLocation: Routes.home,
    debugLogDiagnostics: true,
    routes: [
      // 首页（含底部导航）
      GoRoute(
        path: Routes.home,
        builder: (context, _) => const HomeScreen(),
      ),

      // 添加关心的人
      GoRoute(
        path: Routes.addPartner,
        builder: (context, _) => const AddPartnerScreen(),
      ),

      // 关心的人详情/编辑
      GoRoute(
        path: Routes.partnerDetail,
        builder: (context, state) => PartnerDetailScreen(
          partnerId: state.pathParameters['id']!,
        ),
      ),

      // 提醒配置
      GoRoute(
        path: Routes.reminderConfig,
        builder: (context, state) => ReminderConfigScreen(
          relationshipId: state.pathParameters['partnerId']!,
        ),
      ),

      // 提醒历史
      GoRoute(
        path: Routes.reminderHistory,
        builder: (context, state) => ReminderHistoryScreen(
          configId: state.pathParameters['id']!,
        ),
      ),

      // 成就
      GoRoute(
        path: Routes.achievements,
        builder: (context, _) => const AchievementsScreen(),
      ),

      // AI 助手
      GoRoute(
        path: Routes.aiChat,
        builder: (context, _) => const AiChatScreen(),
      ),

      // 设置
      GoRoute(
        path: Routes.settings,
        builder: (context, _) => const SettingsScreen(),
      ),

      // API Key 管理
      GoRoute(
        path: Routes.apiKeys,
        builder: (context, _) => const ApiKeySetupScreen(),
      ),
    ],
  );
}
