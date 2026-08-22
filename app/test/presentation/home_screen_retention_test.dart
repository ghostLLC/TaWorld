import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/presentation/screens/home/care_graph_view.dart';
import 'package:taworld/presentation/screens/home/home_screen.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'welcome_intro_shown': true});
    await openTestDatabase();
    final db = await DatabaseHelper.database;
    await db.insert('partners', {
      'id': 'partner-1',
      'nickname': '小乐',
      'type': 'partner',
      'status': 'active',
      'created_at': '2026-08-20T00:00:00.000Z',
      'updated_at': '2026-08-20T00:00:00.000Z',
    });
  });

  tearDown(closeTestDatabase);

  testWidgets('partners stay visible after switching away and back', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    await tester.tap(find.text('关心的人').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpUntilFound(tester, find.text('小乐'));
    expect(find.text('加载中...'), findsNothing);

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('关心的人').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('小乐'), findsOneWidget);
    expect(find.text('加载中...'), findsNothing);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  testWidgets('care graph hands selected partner to XiaoNian composer', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    await tester.tap(find.text('关心的人').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpUntilFound(tester, find.text('小乐'));

    await tester.tap(find.text('图谱'));
    await tester.pump();
    expect(find.byType(CareGraphView), findsOneWidget);

    await tester.tap(find.text('小乐'));
    await tester.pump();

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('关心的人').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final chatButton = find.widgetWithText(FilledButton, '聊聊 Ta');
    await tester.ensureVisible(chatButton);
    await tester.tap(chatButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _pumpUntilFound(tester, find.textContaining('小乐的天气'));
    final composer = tester.widget<TextField>(find.byType(TextField).last);
    expect(composer.controller?.text, isEmpty);
    await tester.pump(const Duration(seconds: 1));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Expected widget was not rendered in time: $finder');
}
