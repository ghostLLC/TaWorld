import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:taworld/data/models/reminder_config.dart';
import 'package:taworld/services/reminder_schedule_calculator.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  ReminderConfig config({
    String id = 'config-1',
    String category = 'sleep',
    Map<String, dynamic>? values,
  }) {
    final createdAt = DateTime.utc(2026, 1, 1);
    return ReminderConfig(
      id: id,
      partnerId: 'partner-1',
      category: category,
      enabled: true,
      config: values ?? const <String, dynamic>{},
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  tz.TZDateTime now(
    String locationName,
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
  ]) {
    return tz.TZDateTime(
      tz.getLocation(locationName),
      year,
      month,
      day,
      hour,
      minute,
    );
  }

  test('sleep before today trigger includes today and the next six days', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(
        values: const {'target_sleep_time': '23:00', 'advance_minutes': 30},
      ),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 21),
    );

    expect(occurrences, hasLength(7));
    for (var index = 0; index < occurrences.length; index++) {
      final scheduled = occurrences[index].scheduledTime;
      expect(scheduled.location.name, 'Asia/Shanghai');
      expect(scheduled.year, 2026);
      expect(scheduled.month, 8);
      expect(scheduled.day, 18 + index);
      expect(scheduled.hour, 22);
      expect(scheduled.minute, 30);
    }
  });

  test('sleep after today trigger starts tomorrow', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(
        values: const {'target_sleep_time': '23:00', 'advance_minutes': 30},
      ),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 23),
    );

    expect(occurrences, hasLength(7));
    expect(
      occurrences.first.scheduledTime,
      now('Asia/Shanghai', 2026, 8, 19, 22, 30),
    );
  });

  test('sleep equality is not past and keeps today', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(
        values: const {'target_sleep_time': '23:00', 'advance_minutes': 30},
      ),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 22, 30),
    );

    expect(occurrences, hasLength(7));
    expect(
      occurrences.first.scheduledTime,
      now('Asia/Shanghai', 2026, 8, 18, 22, 30),
    );
  });

  test('advance crossing midnight maps target to the preceding date', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(
        values: const {'target_sleep_time': '00:10', 'advance_minutes': 30},
      ),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 12),
    );

    expect(occurrences, hasLength(7));
    expect(
      occurrences.first.scheduledTime,
      now('Asia/Shanghai', 2026, 8, 18, 23, 40),
    );
    expect(
      occurrences[1].scheduledTime,
      now('Asia/Shanghai', 2026, 8, 19, 23, 40),
    );
  });

  test('calendar generation crosses month and year boundaries', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(
        id: 'boundary',
        values: const {'target_sleep_time': '23:00', 'advance_minutes': 0},
      ),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 12, 30, 23, 30),
      occurrenceCount: 4,
    );

    expect(occurrences.map((item) => item.scheduledTime).toList(), [
      now('Asia/Shanghai', 2026, 12, 31, 23),
      now('Asia/Shanghai', 2027, 1, 1, 23),
      now('Asia/Shanghai', 2027, 1, 2, 23),
      now('Asia/Shanghai', 2027, 1, 3, 23),
    ]);
  });

  test('meal config emits seven occurrences per valid meal', () {
    final values = const {
      'meals': [
        {'name': '早餐', 'target_time': '08:00', 'advance_minutes': 15},
        {'name': '午餐', 'target_time': '12:00', 'advance_minutes': 15},
      ],
    };
    final first = ReminderScheduleCalculator.build(
      config: config(id: 'meals', category: 'meal', values: values),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 6),
    );
    final second = ReminderScheduleCalculator.build(
      config: config(id: 'meals', category: 'meal', values: values),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 6),
    );

    expect(first, hasLength(14));
    expect(first.map((item) => item.notificationId).toSet(), hasLength(14));
    expect(
      first.map((item) => item.notificationId),
      orderedEquals(second.map((item) => item.notificationId)),
    );
    expect(
      first.every(
        (item) => item.notificationId > 0 && item.notificationId <= 0x7fffffff,
      ),
      isTrue,
    );
    expect(
      first.where((item) => item.title == '🍚 早餐提醒'),
      everyElement(
        isA<ReminderOccurrence>()
            .having((item) => item.body, 'body', '到早餐时间了，提醒小Ta按时吃饭吧')
            .having((item) => item.payload, 'payload', 'configId:meals')
            .having((item) => item.scheduledTime.hour, 'hour', 7)
            .having((item) => item.scheduledTime.minute, 'minute', 45),
      ),
    );
    expect(
      first.where((item) => item.title == '🍚 午餐提醒'),
      everyElement(
        isA<ReminderOccurrence>()
            .having((item) => item.body, 'body', '到午餐时间了，提醒小Ta按时吃饭吧')
            .having((item) => item.scheduledTime.hour, 'hour', 11)
            .having((item) => item.scheduledTime.minute, 'minute', 45),
      ),
    );
  });

  test('empty meal list returns no occurrences', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(category: 'meal', values: const {'meals': []}),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 6),
    );

    expect(occurrences, isEmpty);
  });

  test('weather config emits seven occurrences at 08:00', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(id: 'weather', category: 'weather'),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 7),
    );

    expect(occurrences, hasLength(7));
    expect(
      occurrences.every(
        (item) =>
            item.scheduledTime.hour == 8 && item.scheduledTime.minute == 0,
      ),
      isTrue,
    );
    expect(occurrences.first.title, '🌦️ 天气关注');
    expect(occurrences.first.body, '新的一天开始了，看看小Ta那边的天气吧');
    expect(occurrences.first.payload, 'configId:weather');
  });

  test('custom config returns no occurrences', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(category: 'custom', values: const {'anything': true}),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 7),
    );

    expect(occurrences, isEmpty);
  });

  test('invalid sleep time or advance returns no occurrences', () {
    final invalidConfigs = <Map<String, dynamic>>[
      const {'target_sleep_time': '25:90', 'advance_minutes': 0},
      const {'target_sleep_time': 'not-a-time', 'advance_minutes': 0},
      const {'target_sleep_time': '8:00', 'advance_minutes': 0},
      const {'target_sleep_time': '08:0', 'advance_minutes': 0},
      const {'target_sleep_time': '08:00', 'advance_minutes': 15.5},
      const {'target_sleep_time': '08:00', 'advance_minutes': '15'},
      const {'target_sleep_time': '08:00', 'advance_minutes': -1},
      const {'target_sleep_time': '08:00', 'advance_minutes': 1441},
    ];

    for (final values in invalidConfigs) {
      final occurrences = ReminderScheduleCalculator.build(
        config: config(values: values),
        partnerName: '小Ta',
        now: now('Asia/Shanghai', 2026, 8, 18, 7),
      );
      expect(occurrences, isEmpty, reason: values.toString());
    }
  });

  test('invalid meal item is skipped while valid items remain scheduled', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(
        category: 'meal',
        values: const {
          'meals': [
            {'name': '错误', 'target_time': '25:90', 'advance_minutes': 15},
            {'name': '早餐', 'target_time': '08:00', 'advance_minutes': 15},
          ],
        },
      ),
      partnerName: '小Ta',
      now: now('Asia/Shanghai', 2026, 8, 18, 6),
    );

    expect(occurrences, hasLength(7));
    expect(occurrences.every((item) => item.title == '🍚 早餐提醒'), isTrue);
  });

  test('Los Angeles occurrences keep wall-clock time across DST', () {
    final occurrences = ReminderScheduleCalculator.build(
      config: config(
        id: 'dst',
        values: const {'target_sleep_time': '08:00', 'advance_minutes': 0},
      ),
      partnerName: '小Ta',
      now: now('America/Los_Angeles', 2026, 3, 7, 7),
    );

    expect(occurrences, hasLength(7));
    expect(
      occurrences.every(
        (item) =>
            item.scheduledTime.hour == 8 && item.scheduledTime.minute == 0,
      ),
      isTrue,
    );
    expect(
      occurrences[0].scheduledTime.timeZoneOffset,
      const Duration(hours: -8),
    );
    expect(
      occurrences[1].scheduledTime.timeZoneOffset,
      const Duration(hours: -7),
    );
    expect(occurrences[0].scheduledTime.day, 7);
    expect(occurrences[1].scheduledTime.day, 8);
  });
}
