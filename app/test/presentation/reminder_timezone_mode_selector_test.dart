import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/presentation/widgets/reminder_timezone_mode_selector.dart';

void main() {
  final timestamp = DateTime.utc(2026, 1, 1);

  Partner partner({required bool confirmed}) => Partner(
    id: 'partner-1',
    nickname: '小乐',
    type: 'friend',
    timezoneId: 'America/New_York',
    timezoneConfirmed: confirmed,
    status: 'active',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  test('partner mode is available only for a confirmed IANA timezone', () {
    expect(
      ReminderTimezoneModeSelector.normalize(
        'partner',
        partner(confirmed: true),
      ),
      'partner',
    );
    expect(
      ReminderTimezoneModeSelector.normalize(
        'partner',
        partner(confirmed: false),
      ),
      'user',
    );
  });

  testWidgets('shows both wall-clock choices and an unconfirmed warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderTimezoneModeSelector(
            value: 'partner',
            partner: partner(confirmed: false),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('我的时间'), findsOneWidget);
    expect(find.text('小乐当地'), findsOneWidget);
    expect(find.textContaining('尚未确认对方时区'), findsOneWidget);
  });
}
