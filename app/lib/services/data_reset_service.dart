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
import 'local/local_user_service.dart';
import 'local/partner_service.dart';
import 'reminder_health_service.dart';
import 'theme_service.dart';

abstract final class DataResetService {
  static Future<void> reset() async {
    await AiService.stopAndWait();
    await DatabaseHelper.withMaintenance(() async {
      await BackgroundTaskService.cancelAll();
      await NotificationService.cancelAll();
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
      await ApiKeyStore.clear();
      await (await SharedPreferences.getInstance()).clear();
      final documents = await getApplicationDocumentsDirectory();
      for (final name in ['avatars', 'chat_images']) {
        final directory = Directory(p.join(documents.path, name));
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      final rollback = File(
        '${await DatabaseHelper.getDatabasePath()}.pre_import_backup',
      );
      if (await rollback.exists()) await rollback.delete();
      await LocalUserService.createUser(nickname: '');
    });
    await ThemeService.instance.init();
    ReminderHealthService.current.value = null;
    PartnerService.notifyRefresh();
    await BackgroundTaskService.registerAll();
  }
}
