import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taworld/presentation/screens/ai_home/ai_home_screen.dart';
import 'package:taworld/presentation/widgets/widgets.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await openTestDatabase();
  });

  tearDown(closeTestDatabase);

  testWidgets('first onboarding greeting waits behind a left activity bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiHomeScreen())),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilActivity(tester);

    expect(find.text('你好呀，我是小念'), findsNothing);
    expect(find.byType(TaThinkingDots), findsOneWidget);
    expect(
      tester.getCenter(find.byType(TaThinkingDots)).dx,
      lessThan(tester.getSize(find.byType(AiHomeScreen)).width / 2),
    );

    await tester.pump(const Duration(milliseconds: 1799));
    expect(find.text('你好呀，我是小念'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('你好呀，我是小念'), findsOneWidget);
    await _flushAsyncWork(tester);

    // Finish the remaining onboarding timers before the test tears down.
    await tester.pump(const Duration(milliseconds: 2100));
    await _flushAsyncWork(tester);
    await tester.pump(const Duration(milliseconds: 2100));
    await _flushAsyncWork(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets(
    'onboarding messages arrive separately then focus the sole composer',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AiHomeScreen())),
      );
      await _pumpUntilLoaded(tester);
      await _pumpUntilActivity(tester);

      await tester.pump(const Duration(milliseconds: 1800));
      expect(find.text('你好呀，我是小念'), findsOneWidget);
      expect(find.text('我可以帮你关注在乎的人的天气、写温暖的关怀语、设置贴心提醒'), findsNothing);
      await _flushAsyncWork(tester);

      await tester.pump(const Duration(milliseconds: 2099));
      expect(find.text('我可以帮你关注在乎的人的天气、写温暖的关怀语、设置贴心提醒'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('我可以帮你关注在乎的人的天气、写温暖的关怀语、设置贴心提醒'), findsOneWidget);
      expect(find.text('先来告诉我一个你在意的人吧'), findsNothing);
      await _flushAsyncWork(tester);

      await tester.pump(const Duration(milliseconds: 2099));
      expect(find.text('先来告诉我一个你在意的人吧'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await _flushAsyncWork(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('先来告诉我一个你在意的人吧'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      final composer = tester.widget<TextField>(find.byType(TextField));
      expect(composer.focusNode, isNotNull);
      expect(composer.focusNode!.hasFocus, isTrue);
    },
  );
}

Future<void> _flushAsyncWork(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final composerHint = find.text('问我任何关于关怀的问题...');
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (composerHint.evaluate().isNotEmpty) return;
  }
  fail('AI home did not finish loading');
}

Future<void> _pumpUntilActivity(WidgetTester tester) async {
  final activity = find.byType(TaThinkingDots);
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (activity.evaluate().isNotEmpty) return;
  }
  fail('Onboarding activity bubble did not appear');
}
