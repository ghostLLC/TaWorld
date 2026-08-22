import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/data/models/reminder_occurrence_record.dart';
import 'package:taworld/presentation/screens/ai_home/reminder_follow_up_card.dart';
import 'package:taworld/services/reminder_occurrence_service.dart';

void main() {
  testWidgets('follow-up card keeps three responses concise', (tester) async {
    final responses = <ReminderUserResponse>[];
    final now = DateTime.utc(2026, 8, 22, 8);
    final occurrence = ReminderOccurrenceRecord(
      id: 'occ-1',
      configId: 'config-1',
      subjectKind: 'partner',
      subjectId: 'partner-1',
      status: 'scheduled',
      scheduledFor: now,
      message: '提醒小乐带伞',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderFollowUpCard(
            occurrence: occurrence,
            onResponse: responses.add,
          ),
        ),
      ),
    );

    expect(find.text('这条提醒处理好了吗？'), findsOneWidget);
    expect(find.text('提醒小乐带伞'), findsOneWidget);
    expect(find.text('已经处理'), findsOneWidget);
    expect(find.text('5分钟后'), findsOneWidget);
    expect(find.text('已过时'), findsOneWidget);

    await tester.tap(find.text('5分钟后'));
    expect(responses, [ReminderUserResponse.snooze]);
  });
}
