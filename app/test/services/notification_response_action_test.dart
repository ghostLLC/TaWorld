import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/services/notification_service.dart';

void main() {
  test('notification actions map to the three concise reminder responses', () {
    expect(
      ReminderNotificationAction.fromId('reminder_done'),
      ReminderNotificationAction.done,
    );
    expect(
      ReminderNotificationAction.fromId('reminder_snooze_5'),
      ReminderNotificationAction.snooze,
    );
    expect(
      ReminderNotificationAction.fromId('reminder_outdated'),
      ReminderNotificationAction.outdated,
    );
    expect(ReminderNotificationAction.fromId('unknown'), isNull);
  });
}
