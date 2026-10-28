import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/reminder_health/reminder_health_screen.dart';
import 'package:taworld/services/reminder_health_service.dart';

ReminderHealth _health({bool issue = false, int unknown = 0}) {
  return ReminderHealth(
    checkedAt: DateTime(2026, 10, 28),
    pushEnabled: true,
    notificationAllowed: true,
    exactAllowed: true,
    channelAllowed: true,
    configCount: 1,
    pendingCount: 1,
    observedCount: 0,
    acknowledgedCount: 0,
    unknownCount: unknown,
    issues: issue ? const ['需要处理测试问题'] : const [],
    nextAt: DateTime(2026, 10, 29, 8),
  );
}

void main() {
  tearDown(() => ReminderHealthService.current.value = null);

  testWidgets('healthy reminders do not occupy the primary conversation', (
    tester,
  ) async {
    ReminderHealthService.current.value = _health();
    await tester.pumpWidget(const MaterialApp(home: ReminderHealthCard()));
    expect(find.byType(InkWell), findsNothing);

    ReminderHealthService.current.value = _health(issue: true);
    await tester.pump();
    expect(find.text('需要处理测试问题'), findsOneWidget);

    ReminderHealthService.current.value = _health(unknown: 2);
    await tester.pump();
    expect(find.textContaining('无法确认'), findsOneWidget);
  });
}
