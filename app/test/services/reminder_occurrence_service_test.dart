import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/data/models/reminder_config.dart';
import 'package:taworld/data/models/partner.dart';
import 'package:taworld/services/reminder_occurrence_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

  final createdAt = DateTime.utc(2026, 8, 22);
  late ReminderConfig config;

  setUp(() async {
    config = ReminderConfig(
      id: 'config-1',
      partnerId: 'partner-1',
      category: 'sleep',
      enabled: true,
      config: const {'target_sleep_time': '23:00', 'advance_minutes': 30},
      timezoneMode: 'partner',
      subjectKind: 'partner',
      subjectId: 'partner-1',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final db = await DatabaseHelper.database;
    final partner = Partner(
      id: 'partner-1',
      nickname: '小乐',
      type: 'partner',
      status: 'active',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await db.insert('partners', partner.toMap());
    await db.insert('reminder_configs', config.toMap());
  });

  test('scheduled occurrences are idempotent per config and instant', () async {
    final scheduledFor = DateTime.utc(2026, 8, 22, 14, 30);
    final first = await ReminderOccurrenceService.ensureScheduled(
      config: config,
      scheduledFor: scheduledFor,
      message: '提醒小乐早点休息',
    );
    final second = await ReminderOccurrenceService.ensureScheduled(
      config: config,
      scheduledFor: scheduledFor,
      message: '提醒小乐早点休息',
    );

    expect(second.id, first.id);
    expect(await ReminderOccurrenceService.getAll(), hasLength(1));
  });

  test('a busy response snoozes the same occurrence', () async {
    final occurrence = await ReminderOccurrenceService.ensureScheduled(
      config: config,
      scheduledFor: DateTime.utc(2026, 8, 22, 14, 30),
      message: '提醒小乐早点休息',
    );
    final now = DateTime.utc(2026, 8, 22, 14, 31);

    final updated = await ReminderOccurrenceService.respond(
      occurrence.id,
      ReminderUserResponse.snooze,
      now: now,
      snoozeDuration: const Duration(minutes: 5),
    );

    expect(updated.status, 'snoozed');
    expect(updated.response, 'snooze');
    expect(updated.snoozedUntil, now.add(const Duration(minutes: 5)));
  });

  test('due and elapsed reminders are offered for follow-up', () async {
    final now = DateTime.utc(2026, 8, 22, 15);
    await ReminderOccurrenceService.ensureScheduled(
      config: config,
      scheduledFor: now.subtract(const Duration(minutes: 10)),
      message: '提醒小乐早点休息',
    );

    expect(
      await ReminderOccurrenceService.pendingFollowUps(now: now),
      hasLength(1),
    );
  });
}
