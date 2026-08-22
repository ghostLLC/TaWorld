import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/data/models/reminder_config.dart';
import 'package:taworld/services/reminder_tool_planner.dart';

void main() {
  test('self reminder uses the user clock without requiring a partner', () {
    final result = ReminderToolPlanner.parse({
      'subject': 'self',
      'category': 'sleep',
      'time': '23:10',
    });

    expect(result.error, isNull);
    expect(result.plan!.isSelfReminder, isTrue);
    expect(result.plan!.partnerName, '你');
    expect(result.plan!.timezoneMode, 'user');
  });

  setUpAll(tz_data.initializeTimeZones);

  final timestamp = DateTime.utc(2026, 1, 1);

  Partner partner({String? timezoneId, bool confirmed = false}) => Partner(
    id: 'partner-1',
    nickname: '小乐',
    type: 'friend',
    timezoneId: timezoneId,
    timezoneConfirmed: confirmed,
    status: 'active',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  ReminderConfig weatherConfig(String id, String mode) => ReminderConfig(
    id: id,
    partnerId: 'partner-1',
    category: 'weather',
    enabled: true,
    config: {'mode': mode},
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  test('daily weather digest keeps user wall-clock semantics', () {
    final result = ReminderToolPlanner.parse({
      'partner_name': '小乐',
      'category': 'weather',
      'weather_mode': 'daily_digest',
      'time': '8:05',
      'time_basis': 'user',
    });

    expect(result.error, isNull);
    final plan = result.plan!;
    expect(plan.timezoneMode, 'user');
    expect(plan.config['mode'], 'daily_digest');
    expect(plan.config['digest_time'], '08:05');
  });

  test('weather change monitoring uses a partner-local monitoring window', () {
    final result = ReminderToolPlanner.parse({
      'partner_name': '小乐',
      'category': 'weather',
      'weather_mode': 'weather_change',
      'time_basis': 'partner',
      'timezone_id': 'Asia/Singapore',
      'monitor_start': '7:30',
      'monitor_end': '22:00',
      'lead_minutes': 240,
      'notify_conditions': ['rain', 'temperature_drop'],
    });

    expect(result.error, isNull);
    final plan = result.plan!;
    expect(plan.timezoneMode, 'partner');
    expect(plan.timezoneId, 'Asia/Singapore');
    expect(plan.config, containsPair('mode', 'weather_change'));
    expect(plan.config, containsPair('monitor_start', '07:30'));
    expect(plan.config, containsPair('monitor_end', '22:00'));
    expect(plan.config, containsPair('lead_minutes', 240));
    expect(plan.config['notify_conditions'], ['rain', 'temperature_drop']);
  });

  test('sleep reminders default to the partner wall clock', () {
    final result = ReminderToolPlanner.parse({
      'partner_name': '妈妈',
      'category': 'sleep',
      'time': '23:00',
    });

    expect(result.error, isNull);
    expect(result.plan!.timezoneMode, 'partner');
    expect(result.plan!.config['target_sleep_time'], '23:00');
  });

  test('daily reminders reject invalid wall-clock values', () {
    final result = ReminderToolPlanner.parse({
      'partner_name': '小乐',
      'category': 'weather',
      'weather_mode': 'daily_digest',
      'time': '25:10',
    });

    expect(result.plan, isNull);
    expect(result.error, contains('时间'));
  });

  test('weather change monitoring does not require a daily digest time', () {
    final result = ReminderToolPlanner.parse({
      'partner_name': '小乐',
      'category': 'weather',
      'weather_mode': 'weather_change',
    });

    expect(result.error, isNull);
    expect(result.plan!.config['mode'], 'weather_change');
    expect(result.plan!.config['monitor_start'], '07:00');
    expect(result.plan!.config['monitor_end'], '23:00');
  });

  test('unconfirmed profile timezone cannot satisfy partner-local plan', () {
    final plan = ReminderToolPlanner.parse({
      'partner_name': '小乐',
      'category': 'sleep',
      'time': '23:00',
    }).plan!;

    expect(
      ReminderToolPlanner.resolveTimezoneId(
        plan: plan,
        partner: partner(timezoneId: 'America/New_York', confirmed: false),
      ),
      isNull,
    );
  });

  test('explicit or confirmed IANA timezone satisfies partner-local plan', () {
    final explicitPlan = ReminderToolPlanner.parse({
      'partner_name': '小乐',
      'category': 'sleep',
      'time': '23:00',
      'timezone_id': 'Asia/Singapore',
    }).plan!;
    final profilePlan = ReminderToolPlanner.parse({
      'partner_name': '小乐',
      'category': 'sleep',
      'time': '23:00',
    }).plan!;

    expect(
      ReminderToolPlanner.resolveTimezoneId(
        plan: explicitPlan,
        partner: partner(timezoneId: 'America/New_York', confirmed: false),
      ),
      'Asia/Singapore',
    );
    expect(
      ReminderToolPlanner.resolveTimezoneId(
        plan: profilePlan,
        partner: partner(timezoneId: 'America/New_York', confirmed: true),
      ),
      'America/New_York',
    );
  });

  test('weather deletion is ambiguous when both modes exist', () {
    final selection = ReminderToolPlanner.selectDeletionTargets([
      weatherConfig('daily', 'daily_digest'),
      weatherConfig('change', 'weather_change'),
    ], category: 'weather');

    expect(selection.targets, isEmpty);
    expect(selection.error, contains('模式'));
  });

  test('weather deletion selects only the requested mode', () {
    final selection = ReminderToolPlanner.selectDeletionTargets(
      [
        weatherConfig('daily', 'daily_digest'),
        weatherConfig('change', 'weather_change'),
      ],
      category: 'weather',
      weatherMode: 'weather_change',
    );

    expect(selection.error, isNull);
    expect(selection.targets.map((config) => config.id), ['change']);
  });
}
