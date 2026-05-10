/// TaWorld API 路径常量
///
/// 所有 API 端点的路径定义。禁止在代码中硬编码 URL。
library;

abstract final class ApiEndpoints {
  static const String prefix = '/api/v1';

  // ---- 认证 ----
  static const String register = '$prefix/auth/register';
  static const String login = '$prefix/auth/login';
  static const String refresh = '$prefix/auth/refresh';

  // ---- 用户 ----
  static const String me = '$prefix/users/me';
  static const String myStats = '$prefix/users/me/stats';
  static const String myLocation = '$prefix/users/me/location';
  static const String myDevices = '$prefix/users/me/devices';
  static const String myAvatar = '$prefix/users/me/avatar';
  static const String myAchievements = '$prefix/users/me/achievements';

  // ---- 关系 ----
  static const String relationships = '$prefix/relationships';
  static const String invite = '$prefix/relationships/invite';
  static const String join = '$prefix/relationships/join';
  static String relationship(String id) => '$prefix/relationships/$id';

  // ---- 提醒 ----
  static String reminders(String relId) =>
      '$prefix/relationships/$relId/reminders';
  static String reminder(String id) => '$prefix/reminders/$id';
  static String sendReminder(String id) => '$prefix/reminders/$id/send';
  static String confirmReminder(String id) => '$prefix/reminders/$id/confirm';
  static String reminderLogs(String id) => '$prefix/reminders/$id/logs';
  static const String reminderStats = '$prefix/reminders/stats';

  // ---- 天气 ----
  static const String weather = '$prefix/weather/current';

  // ---- 成就 ----
  static const String achievements = '$prefix/achievements';

  // ---- AI ----
  static const String aiSuggest = '$prefix/ai/suggest';
  static const String aiChat = '$prefix/ai/chat';

  // ---- 系统 ----
  static const String config = '$prefix/config';
  static const String health = '/health';
}
