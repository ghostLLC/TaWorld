import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/app/theme.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/presentation/screens/achievements/achievements_screen.dart';
import 'package:taworld/presentation/widgets/ta_loading.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await openTestDatabase();
    final db = await DatabaseHelper.database;
    await db.insert('partners', {
      'id': 'partner-1',
      'nickname': '小乐',
      'type': 'family',
      'status': 'active',
      'created_at': '2026-10-01T00:00:00.000Z',
      'updated_at': '2026-10-01T00:00:00.000Z',
    });
    await db.insert('reminder_configs', {
      'id': 'config-1',
      'partner_id': 'partner-1',
      'subject_kind': 'partner',
      'subject_id': 'partner-1',
      'category': 'weather',
      'enabled': 1,
      'config': jsonEncode({'mode': 'daily_digest', 'digest_time': '08:00'}),
      'timezone_mode': 'user',
      'created_at': '2026-10-01T00:00:00.000Z',
      'updated_at': '2026-10-01T00:00:00.000Z',
    });
    await db.insert('reminder_logs', {
      'id': 'log-1',
      'config_id': 'config-1',
      'partner_id': 'partner-1',
      'subject_kind': 'partner',
      'subject_id': 'partner-1',
      'message': '天气提醒',
      'status': 'confirmed',
      'triggered_at': '2026-10-28T08:00:00.000Z',
      'sent_at': '2026-10-28T08:00:00.000Z',
      'confirmed_at': '2026-10-28T08:05:00.000Z',
    });
  });

  tearDown(closeTestDatabase);

  testWidgets('existing unlocked achievements establish a quiet baseline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: TaTheme.light, home: const AchievementsScreen()),
    );

    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('初次守护').evaluate().isNotEmpty) break;
    }

    expect(find.text('初次守护'), findsOneWidget);
    expect(find.byType(TaCelebrateAnimation), findsNothing);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
