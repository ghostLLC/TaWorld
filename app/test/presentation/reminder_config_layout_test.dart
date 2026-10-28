import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/app/theme.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/presentation/screens/reminder_config/reminder_config_screen.dart';

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
      'category': 'custom',
      'enabled': 1,
      'config': jsonEncode({
        'message': '记得问问妈妈最近复查结果，并确认下次复诊时间',
        'target_time': '09:00',
        'repeat_daily': true,
      }),
      'timezone_mode': 'user',
      'created_at': '2026-10-01T00:00:00.000Z',
      'updated_at': '2026-10-01T00:00:00.000Z',
    });
  });

  tearDown(closeTestDatabase);

  testWidgets('reminder summary and actions remain readable at 200 percent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: TaTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const ReminderConfigScreen(partnerId: 'partner-1'),
        ),
      ),
    );

    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('复查结果').evaluate().isNotEmpty) break;
    }

    final textValues = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .toList();
    final summaryFinder = find.textContaining('复查结果');
    expect(summaryFinder, findsOneWidget, reason: 'Rendered text: $textValues');
    final summary = tester.widget<Text>(summaryFinder);
    expect(summary.maxLines, greaterThanOrEqualTo(2));
    expect(find.byTooltip('新建提醒'), findsNothing);
    expect(find.widgetWithText(FloatingActionButton, '新建提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
