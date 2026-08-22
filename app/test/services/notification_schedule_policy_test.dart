import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/services/notification_service.dart';

void main() {
  test('uses exact scheduling only when Android grants exact alarms', () {
    expect(
      NotificationSchedulePolicy.modeFor(canScheduleExact: true),
      AndroidScheduleMode.exactAllowWhileIdle,
    );
    expect(
      NotificationSchedulePolicy.modeFor(canScheduleExact: false),
      AndroidScheduleMode.inexactAllowWhileIdle,
    );
    expect(
      NotificationSchedulePolicy.modeFor(canScheduleExact: null),
      AndroidScheduleMode.inexactAllowWhileIdle,
    );
  });
}
