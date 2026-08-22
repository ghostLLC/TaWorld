import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/data/models/reminder_config.dart';
import 'package:taworld/services/reminder_scheduler.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('scheduler binds partner timezone to calculator', () {
    final timestamp = DateTime.utc(2026, 1, 1);
    final partner = Partner(
      id: 'partner-1',
      nickname: '小乐',
      type: 'friend',
      timezoneId: 'America/New_York',
      timezoneConfirmed: true,
      status: 'active',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final config = ReminderConfig(
      id: 'config-1',
      partnerId: partner.id,
      category: 'weather',
      enabled: true,
      config: const {'mode': 'daily_digest', 'digest_time': '08:00'},
      timezoneMode: 'partner',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final now = tz.TZDateTime(tz.getLocation('Asia/Shanghai'), 2026, 3, 8, 10);

    final occurrences = ReminderScheduler.calculateOccurrences(
      config: config,
      partner: partner,
      now: now,
      occurrenceCount: 1,
    );

    expect(
      occurrences.single.scheduledTime,
      tz.TZDateTime(tz.getLocation('Asia/Shanghai'), 2026, 3, 8, 20),
    );
  });

  test('scheduler rejects an unconfirmed partner timezone', () {
    final timestamp = DateTime.utc(2026, 1, 1);
    final partner = Partner(
      id: 'partner-1',
      nickname: '小乐',
      type: 'friend',
      timezoneId: 'America/New_York',
      timezoneConfirmed: false,
      status: 'active',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final config = ReminderConfig(
      id: 'config-1',
      partnerId: partner.id,
      category: 'sleep',
      enabled: true,
      config: const {'target_sleep_time': '23:00', 'advance_minutes': 30},
      timezoneMode: 'partner',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final occurrences = ReminderScheduler.calculateOccurrences(
      config: config,
      partner: partner,
      now: tz.TZDateTime(tz.getLocation('Asia/Shanghai'), 2026, 3, 8, 10),
      occurrenceCount: 1,
    );

    expect(occurrences, isEmpty);
  });

  test(
    'batch executor builds the plan before cancelling and retries the full plan',
    () async {
      final events = <String>[];
      var firstAttempt = true;

      final executor = ReminderScheduleBatchExecutor<String>(
        buildPlan: () {
          events.add('build');
          return const ['a', 'b', 'c'];
        },
        cancelAll: () async {
          events.add('cancel');
        },
        schedule: (item) async {
          events.add('schedule:$item');
          if (firstAttempt && item == 'b') {
            firstAttempt = false;
            throw StateError('temporary scheduling failure');
          }
        },
      );

      await executor.execute();

      expect(events, [
        'build',
        'cancel',
        'schedule:a',
        'schedule:b',
        'schedule:a',
        'schedule:b',
        'schedule:c',
      ]);
    },
  );

  test('batch executor throws after the complete retry fails', () async {
    final events = <String>[];
    final executor = ReminderScheduleBatchExecutor<String>(
      buildPlan: () {
        events.add('build');
        return const ['a', 'b'];
      },
      cancelAll: () async {
        events.add('cancel');
      },
      schedule: (item) async {
        events.add('schedule:$item');
        throw StateError('permanent scheduling failure for $item');
      },
    );

    late ReminderScheduleBatchException failure;
    try {
      await executor.execute();
      fail('expected the batch executor to throw');
    } on ReminderScheduleBatchException catch (error) {
      failure = error;
    }

    expect(failure.firstFailure.toString(), contains('permanent'));
    expect(failure.retryFailure.toString(), contains('permanent'));
    expect(events, ['build', 'cancel', 'schedule:a', 'schedule:a']);
  });

  test(
    'batch executor cancels stale notifications for an empty plan',
    () async {
      final events = <String>[];
      final executor = ReminderScheduleBatchExecutor<String>(
        buildPlan: () {
          events.add('build');
          return const <String>[];
        },
        cancelAll: () async {
          events.add('cancel');
        },
        schedule: (item) async {
          events.add('schedule:$item');
        },
      );

      await executor.execute();

      expect(events, ['build', 'cancel']);
    },
  );
}
