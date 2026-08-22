import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/data/models/reminder_config.dart';

void main() {
  test('partner persists confirmed IANA timezone metadata', () {
    final createdAt = DateTime.utc(2026, 8, 22);
    final partner = Partner(
      id: 'partner-1',
      nickname: '小乐',
      type: 'friend',
      timezoneId: 'Asia/Singapore',
      timezoneSource: 'user_confirmed',
      timezoneConfirmed: true,
      status: 'active',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final restored = Partner.fromMap(partner.toMap());

    expect(restored.timezoneId, 'Asia/Singapore');
    expect(restored.timezoneSource, 'user_confirmed');
    expect(restored.timezoneConfirmed, isTrue);
  });

  test('legacy partner rows default to an unconfirmed unknown timezone', () {
    final partner = Partner.fromMap({
      'id': 'legacy',
      'nickname': 'Ta',
      'type': 'friend',
      'status': 'active',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });

    expect(partner.timezoneId, isNull);
    expect(partner.timezoneSource, isNull);
    expect(partner.timezoneConfirmed, isFalse);
  });

  test('reminder persists user or partner wall-clock semantics', () {
    final createdAt = DateTime.utc(2026, 8, 22);
    final reminder = ReminderConfig(
      id: 'reminder-1',
      partnerId: 'partner-1',
      category: 'weather',
      enabled: true,
      config: const {'mode': 'daily_digest', 'digest_time': '08:30'},
      timezoneMode: 'partner',
      timezoneId: 'America/Los_Angeles',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final restored = ReminderConfig.fromMap(reminder.toMap());

    expect(restored.timezoneMode, 'partner');
    expect(restored.timezoneId, 'America/Los_Angeles');
    expect(reminder.copyWith(clearTimezoneId: true).timezoneId, isNull);
  });

  test('legacy reminder rows derive a partner subject', () {
    final reminder = ReminderConfig.fromMap({
      'id': 'legacy-reminder',
      'partner_id': 'partner-legacy',
      'category': 'custom',
      'enabled': 1,
      'config': '{}',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });

    expect(reminder.subjectKind, 'partner');
    expect(reminder.subjectId, 'partner-legacy');
    expect(reminder.isSelfReminder, isFalse);
  });

  test('self reminder round-trips without a synthetic partner', () {
    final createdAt = DateTime.utc(2026, 8, 22);
    final reminder = ReminderConfig(
      id: 'self-reminder',
      partnerId: '',
      subjectKind: 'user',
      subjectId: 'local-user',
      category: 'custom',
      enabled: true,
      config: const {'message': '起来活动一下'},
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final map = reminder.toMap();
    final restored = ReminderConfig.fromMap(map);

    expect(map['partner_id'], isNull);
    expect(restored.subjectKind, 'user');
    expect(restored.subjectId, 'local-user');
    expect(restored.partnerId, isEmpty);
    expect(restored.isSelfReminder, isTrue);
  });
}
