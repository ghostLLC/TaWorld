import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/local/local_reminder_service.dart';
import 'package:taworld/services/local/local_user_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

  test(
    'care statistics count acknowledgements, not notification deliveries',
    () async {
      final db = await DatabaseHelper.database;
      final timestamp = DateTime.now().toUtc().toIso8601String();
      await db.insert('partners', {
        'id': 'care-person',
        'nickname': 'Ta',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await db.insert('reminder_configs', {
        'id': 'care-config',
        'partner_id': 'care-person',
        'category': 'custom',
        'enabled': 1,
        'config': '{}',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      for (final status in ['sent', 'pending', 'ignored']) {
        await db.insert('reminder_logs', {
          'id': 'care-$status',
          'config_id': 'care-config',
          'status': status,
          'message': 'Remember Ta',
          'triggered_at': timestamp,
        });
      }
      expect((await LocalReminderService.getStats())['totalCount'], 0);
      expect((await LocalUserService.getStats())['reminderCount'], 0);

      await LocalReminderService.confirmReminder('care-sent');
      await LocalReminderService.confirmReminder('care-sent');
      final care = await LocalReminderService.getStats();
      expect(care['totalCount'], 1);
      expect(care['byCategory'], {'custom': 1});
      expect(care['streakDays'], 1);
      expect((await LocalUserService.getStats())['reminderCount'], 1);
    },
  );

  test('all reminder configs are loaded once and grouped by partner', () async {
    final db = await DatabaseHelper.database;
    const timestamp = '2026-08-20T00:00:00.000Z';
    for (final id in ['partner-1', 'partner-2']) {
      await db.insert('partners', {
        'id': id,
        'nickname': id,
        'created_at': timestamp,
        'updated_at': timestamp,
      });
    }
    await db.insert('reminder_configs', {
      'id': 'config-1',
      'partner_id': 'partner-1',
      'category': 'weather',
      'enabled': 1,
      'config': '{}',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await db.insert('reminder_configs', {
      'id': 'config-2',
      'partner_id': 'partner-1',
      'category': 'sleep',
      'enabled': 0,
      'config': '{}',
      'created_at': '2026-08-20T00:01:00.000Z',
      'updated_at': '2026-08-20T00:01:00.000Z',
    });
    await db.insert('reminder_configs', {
      'id': 'config-3',
      'partner_id': 'partner-2',
      'category': 'meal',
      'enabled': 1,
      'config': '{}',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    final grouped = await LocalReminderService.getAllConfigs();

    expect(grouped.keys, containsAll(['partner-1', 'partner-2']));
    expect(grouped['partner-1']!.map((config) => config.id), [
      'config-1',
      'config-2',
    ]);
    expect(grouped['partner-1']!.last.enabled, isFalse);
    expect(grouped['partner-2']!.single.id, 'config-3');
  });

  test('create and update persist reminder timezone semantics', () async {
    final db = await DatabaseHelper.database;
    const timestamp = '2026-08-20T00:00:00.000Z';
    await db.insert('partners', {
      'id': 'partner-1',
      'nickname': 'Ta',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    final created = await LocalReminderService.createConfig(
      partnerId: 'partner-1',
      category: 'weather',
      timezoneMode: 'partner',
      timezoneId: 'Asia/Singapore',
      config: const {'mode': 'daily_digest', 'digest_time': '08:00'},
    );

    expect(created.timezoneMode, 'partner');
    expect(created.timezoneId, 'Asia/Singapore');

    await LocalReminderService.updateConfig(
      created.id,
      timezoneMode: 'user',
      timezoneId: 'Asia/Shanghai',
    );
    final updated = (await LocalReminderService.getConfigs('partner-1')).single;

    expect(updated.timezoneMode, 'user');
    expect(updated.timezoneId, 'Asia/Shanghai');

    await LocalReminderService.updateConfig(
      created.id,
      timezoneMode: 'partner',
      clearTimezoneId: true,
    );
    final cleared = (await LocalReminderService.getConfigs('partner-1')).single;
    expect(cleared.timezoneMode, 'partner');
    expect(cleared.timezoneId, isNull);
  });
}
