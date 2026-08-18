// Basic smoke test for TaWorld standalone app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taworld/app/app.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await openTestDatabase();
  });

  tearDown(() async {
    await closeTestDatabase();
  });

  testWidgets('TaWorldApp opens the first-run onboarding screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TaWorldApp());
    for (var frame = 0; frame < 20; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Ta的世界').evaluate().isNotEmpty) break;
    }

    expect(find.text('Ta的世界'), findsOneWidget);
    expect(find.text('记录你的每一份关心'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
