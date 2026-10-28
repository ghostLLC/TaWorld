import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/database_helper.dart';
import 'ai_service.dart';
import 'api_key_store.dart';
import 'background_tasks.dart';
import 'native_notification_bridge.dart';
import 'notification_service.dart';
import 'local/partner_service.dart';
import 'reminder_health_service.dart';
import 'theme_service.dart';

class DataResetDependencies {
  const DataResetDependencies({
    required this.documentsDirectory,
    required this.cancelBackgroundTasks,
    required this.registerBackgroundTasks,
    required this.cancelNotifications,
    required this.clearApiKey,
  });

  final Directory documentsDirectory;
  final Future<void> Function() cancelBackgroundTasks;
  final Future<void> Function() registerBackgroundTasks;
  final Future<void> Function() cancelNotifications;
  final Future<void> Function() clearApiKey;
}

abstract final class DataResetService {
  static Future<void> reset({DataResetDependencies? dependencies}) async {
    final documentsDirectory = dependencies?.documentsDirectory;
    final cancelBackgroundTasks =
        dependencies?.cancelBackgroundTasks ?? BackgroundTaskService.cancelAll;
    final registerBackgroundTasks =
        dependencies?.registerBackgroundTasks ??
        BackgroundTaskService.registerAll;
    final cancelNotifications =
        dependencies?.cancelNotifications ?? NotificationService.cancelAll;
    final clearApiKey = dependencies?.clearApiKey ?? ApiKeyStore.clear;

    await AiService.stopAndWait();
    await DatabaseHelper.withMaintenance(() async {
      await cancelBackgroundTasks();
      await cancelNotifications();
      await NativeNotificationBridge.invoke<bool>('clearEvidence');
      final db = await DatabaseHelper.database;
      await db.transaction((tx) async {
        for (final table in [
          'user_achievements',
          'scheduled_notifications',
          'notification_events',
          'reminder_logs',
          'reminder_occurrences',
          'reminder_configs',
          'chat_attachments',
          'chat_history',
          'ai_pending_messages',
          'graph_positions',
          'partners',
          'users',
          'ai_wiki_facts',
          'ai_conversation_summaries',
          'conversation_chunks',
          'background_runs',
          'tool_operations',
          'runtime_locks',
        ]) {
          await tx.delete(table);
        }
      });
      await clearApiKey();
      await (await SharedPreferences.getInstance()).clear();
      final documents =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      for (final name in ['avatars', 'chat_images']) {
        final directory = Directory(p.join(documents.path, name));
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      final rollback = File(
        '${await DatabaseHelper.getDatabasePath()}.pre_import_backup',
      );
      if (await rollback.exists()) await rollback.delete();
    });
    await ThemeService.instance.init();
    ReminderHealthService.current.value = null;
    PartnerService.notifyRefresh();
    await registerBackgroundTasks();
  }
}
