import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/local/local_achievement_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

  test(
    'achievements reconcile legacy send counts and native confirmations',
    () async {
      final db = await DatabaseHelper.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('partners', {
        'id': 'person',
        'nickname': 'Ta',
        'created_at': now,
        'updated_at': now,
      });
      for (var i = 0; i < 6; i++) {
        await db.insert('reminder_configs', {
          'id': 'config-$i',
          'partner_id': 'person',
          'category': i == 0 ? 'weather' : 'custom',
          'config': '{}',
          'created_at': now,
          'updated_at': now,
        });
      }
      await db.insert('reminder_logs', {
        'id': 'unconfirmed',
        'config_id': 'config-0',
        'status': 'sent',
        'triggered_at': now,
      });
      final weatherId = (await db.query(
        'achievements',
        where: "category = 'weather'",
      )).single['id'];
      await db.insert('user_achievements', {
        'id': 'legacy-inflated',
        'achievement_id': weatherId,
        'progress': 9,
        'unlocked': 1,
        'unlocked_at': now,
      });

      var progress = await LocalAchievementService.getAllWithProgress();
      expect(
        progress.singleWhere((a) => a.achievementName == '初次守护').progress,
        0,
      );
      expect(
        progress.singleWhere((a) => a.achievementName == '初次守护').unlocked,
        isFalse,
      );
      expect(
        progress.singleWhere((a) => a.achievementName == '创意达人').progress,
        5,
      );

      // Native notification actions write confirmed logs even without a UI send call.
      for (var day = 10; day <= 16; day++) {
        final at = DateTime(2026, 8, day, 12).toUtc().toIso8601String();
        await db.insert('reminder_logs', {
          'id': 'confirmed-$day',
          'config_id': 'config-0',
          'status': 'confirmed',
          'triggered_at': at,
          'confirmed_at': at,
        });
      }
      progress = await LocalAchievementService.getAllWithProgress();
      expect(
        progress.singleWhere((a) => a.achievementName == '初次守护').progress,
        7,
      );
      expect(
        progress.singleWhere((a) => a.achievementName == '连续守护7天').unlocked,
        isTrue,
      );
      expect((await LocalAchievementService.getStats())['unlocked'], 3);
      expect(
        await db.query(
          'user_achievements',
          where: 'achievement_id = ?',
          whereArgs: [weatherId],
        ),
        hasLength(1),
      );
    },
  );
}
