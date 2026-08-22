import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/services/background_execution_service.dart';

void main() {
  test('parses native readiness without claiming autostart was granted', () {
    final readiness = BackgroundExecutionReadiness.fromMap({
      'notificationGranted': true,
      'exactAlarmAllowed': false,
      'batteryOptimizationIgnored': false,
      'autoStartGuidanceAvailable': true,
      'autoStartStatusKnown': false,
      'manufacturer': 'Xiaomi',
      'bestEffort': true,
    });

    expect(readiness.notificationGranted, isTrue);
    expect(readiness.exactAlarmAllowed, isFalse);
    expect(readiness.batteryOptimizationIgnored, isFalse);
    expect(readiness.autoStartGuidanceAvailable, isTrue);
    expect(readiness.autoStartStatusKnown, isFalse);
    expect(readiness.manufacturer, 'Xiaomi');
    expect(readiness.bestEffort, isTrue);
    expect(readiness.isFullyReady, isFalse);
  });

  test('missing native fields use conservative defaults', () {
    final readiness = BackgroundExecutionReadiness.fromMap(const {});

    expect(readiness.notificationGranted, isFalse);
    expect(readiness.exactAlarmAllowed, isFalse);
    expect(readiness.batteryOptimizationIgnored, isFalse);
    expect(readiness.autoStartStatusKnown, isFalse);
    expect(readiness.bestEffort, isTrue);
  });
}
