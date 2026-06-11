// Basic smoke test for TaWorld standalone app.

import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/app/app.dart';

void main() {
  testWidgets('TaWorldApp builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(TaWorldApp());
    await tester.pump();
    // App should render — no exceptions thrown.
  });
}
