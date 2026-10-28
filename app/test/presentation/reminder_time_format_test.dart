import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/reminder_history/reminder_history_screen.dart';

void main() {
  test('long reminder timestamps use the device local timezone', () {
    final timestamp = DateTime.utc(2026, 10, 28, 1, 30);
    final local = timestamp.toLocal();
    final expected =
        '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    expect(
      formatReminderTimestamp(timestamp, now: DateTime.utc(2026, 11, 5, 12)),
      expected,
    );
  });

  test('future reminder timestamps show the local scheduled time', () {
    final timestamp = DateTime.utc(2026, 11, 1, 1, 30);
    final local = timestamp.toLocal();
    final expected =
        '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    expect(
      formatReminderTimestamp(timestamp, now: DateTime.utc(2026, 10, 28, 12)),
      expected,
    );
  });

  test('relative reminder timestamps use the absolute time difference', () {
    final now = DateTime.utc(2026, 10, 28, 12);
    expect(
      formatReminderTimestamp(DateTime.utc(2026, 10, 28, 11, 59, 30), now: now),
      '刚刚',
    );
    expect(
      formatReminderTimestamp(DateTime.utc(2026, 10, 28, 11, 30), now: now),
      '30分钟前',
    );
    expect(
      formatReminderTimestamp(DateTime.utc(2026, 10, 28, 10), now: now),
      '2小时前',
    );
  });
}
