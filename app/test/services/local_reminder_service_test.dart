import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/local/local_reminder_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

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
}
