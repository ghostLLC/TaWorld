import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/ai_service.dart';
import 'package:taworld/services/local/local_reminder_service.dart';
import 'package:taworld/services/local/partner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    await DatabaseHelper.configureForTesting(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(DatabaseHelper.resetForTesting);

  test(
    'changing a city never retains coordinates of the previous city',
    () async {
      final person = await PartnerService.add(
        nickname: '妈妈',
        type: 'family',
        city: '广州',
        latitude: 23.13,
        longitude: 113.26,
      );
      await PartnerService.update(person.id, city: '伦敦');
      final saved = (await PartnerService.getById(person.id))!;
      expect(saved.city, '伦敦');
      expect(saved.latitude, isNot(23.13));
      expect(saved.longitude, isNot(113.26));
    },
  );

  test(
    'a broken reminder does not prevent loading intact people and reminders',
    () async {
      final person = await PartnerService.add(nickname: '妈妈', type: 'family');
      await LocalReminderService.createConfig(
        partnerId: person.id,
        category: 'sleep',
      );
      final broken = await LocalReminderService.createConfig(
        partnerId: person.id,
        category: 'meal',
      );
      final db = await DatabaseHelper.database;
      await db.update(
        'reminder_configs',
        {'config': '{broken'},
        where: 'id = ?',
        whereArgs: [broken.id],
      );
      final configs = await LocalReminderService.getAllConfigs();
      expect((await PartnerService.getAll()).single.id, person.id);
      expect(
        configs[person.id]!.where((c) => c.category == 'sleep'),
        hasLength(1),
      );
      expect(
        (await db.query('reminder_configs')).length,
        2,
        reason: 'Malformed source data must be retained for repair',
      );
    },
  );

  test(
    'chat opens the latest page and keeps chronological display order',
    () async {
      final db = await DatabaseHelper.database;
      final start = DateTime.utc(2026, 9, 5);
      for (var i = 1; i <= 55; i++) {
        await db.insert('chat_history', {
          'id': 'm-$i',
          'role': 'user',
          'content': 'message-$i',
          'created_at': start.add(Duration(seconds: i)).toIso8601String(),
        });
      }
      final visible = await AiService.getChatHistory();
      expect(visible, hasLength(50));
      expect(visible.first['content'], 'message-6');
      expect(visible.last['content'], 'message-55');
    },
  );
  test(
    'bad reminder metadata stays visible without hiding valid people',
    () async {
      final person = await PartnerService.add(nickname: '妈妈', type: 'family');
      final config = await LocalReminderService.createConfig(
        partnerId: person.id,
        category: 'sleep',
      );
      final db = await DatabaseHelper.database;
      await db.update(
        'reminder_configs',
        {'created_at': 'invalid', 'enabled': 'invalid'},
        where: 'id = ?',
        whereArgs: [config.id],
      );
      final loaded =
          (await LocalReminderService.getAllConfigs())[person.id]!.single;
      expect(loaded.isValid, isFalse);
      expect((await PartnerService.getAll()).single.id, person.id);
      expect(
        (await db.query('reminder_configs')).single['created_at'],
        'invalid',
      );
    },
  );

  test(
    'moving a person out and restoring retains identity, note and reminders',
    () async {
      final person = await PartnerService.add(
        nickname: '妈妈',
        type: 'family',
        note: '周末散步',
      );
      final config = await LocalReminderService.createConfig(
        partnerId: person.id,
        category: 'sleep',
      );
      await PartnerService.dissolve(person.id);
      expect(await PartnerService.getAll(), isEmpty);
      expect(await PartnerService.getAll(includeDissolved: true), hasLength(1));
      await PartnerService.restore(person.id);
      final restored = (await PartnerService.getAll()).single;
      expect(restored.id, person.id);
      expect(restored.note, '周末散步');
      expect(
        (await LocalReminderService.getConfigs(person.id)).single.id,
        config.id,
      );
    },
  );
}
