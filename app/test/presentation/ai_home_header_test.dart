import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/presentation/screens/ai_home/ai_home_screen.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'welcome_intro_shown': true});
    await openTestDatabase();
    await (await DatabaseHelper.database).insert('partners', {
      'id': 'partner-1',
      'nickname': '小乐',
      'type': 'family',
      'status': 'active',
      'created_at': '2026-10-01T00:00:00.000Z',
      'updated_at': '2026-10-01T00:00:00.000Z',
    });
  });

  tearDown(closeTestDatabase);

  testWidgets('secondary conversation actions use an accessible menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiHomeScreen())),
    );

    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('问我任何关于关怀的问题...').evaluate().isNotEmpty) break;
    }

    final menu = find.byType(PopupMenuButton<String>);
    expect(menu, findsOneWidget);
    expect(tester.widget<PopupMenuButton<String>>(menu).tooltip, '更多操作');
    await tester.tap(menu);
    await tester.pump();

    expect(find.text('查看成就'), findsOneWidget);
    expect(find.text('清空屏幕'), findsOneWidget);
    expect(find.text('清除对话记录'), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 500));
  });
}
