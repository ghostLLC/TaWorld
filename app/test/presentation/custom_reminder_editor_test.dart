import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/presentation/widgets/custom_reminder_editor.dart';
import 'package:taworld/services/timezone_service.dart';

Partner _partner({
  required bool confirmed,
  String timezoneId = 'Asia/Shanghai',
}) {
  final now = DateTime(2026, 10, 1);
  return Partner(
    id: 'partner-1',
    nickname: '小乐',
    type: 'family',
    status: 'active',
    timezoneId: confirmed ? timezoneId : null,
    timezoneSource: confirmed ? 'user_confirmed' : null,
    timezoneConfirmed: confirmed,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUp(() async {
    await TimezoneService.initialize(
      identifierLoader: () async => 'Asia/Shanghai',
    );
  });

  testWidgets('confirmed partner time is returned with the custom config', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog(
                context: context,
                builder: (_) => CustomReminderEditor(
                  initial: const {
                    'message': '每日复查',
                    'target_time': '09:00',
                    'repeat_daily': true,
                  },
                  partner: _partner(confirmed: true),
                  initialTimezoneMode: 'user',
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('小乐当地'));
    await tester.tap(find.text('保存提醒'));
    await tester.pump(const Duration(milliseconds: 500));

    final editResult = result as dynamic;
    expect(editResult.timezoneMode, 'partner');
    expect(editResult.config['message'], '每日复查');
    expect(editResult.config['repeat_daily'], isTrue);
  });

  testWidgets('single reminder is displayed in the partner timezone', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomReminderEditor(
          initial: const {
            'message': '视频通话',
            'scheduled_at': '2026-11-01T01:30:00.000Z',
          },
          partner: _partner(confirmed: true, timezoneId: 'America/New_York'),
          initialTimezoneMode: 'partner',
        ),
      ),
    );

    expect(find.text('2026年10月31日'), findsOneWidget);
    expect(find.text('9:30 PM'), findsOneWidget);
  });

  testWidgets('unconfirmed partner timezone cannot be selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomReminderEditor(
          initial: const {'message': '每日复查'},
          partner: _partner(confirmed: false),
        ),
      ),
    );

    final selector = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    final partnerSegment = selector.segments.firstWhere(
      (segment) => segment.value == 'partner',
    );
    expect(partnerSegment.enabled, isFalse);
  });
}
