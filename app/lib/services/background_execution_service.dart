/// Android background-delivery readiness and settings navigation.
///
/// The service never claims it can grant a system permission. It only reports
/// verifiable state and opens the appropriate system screen for the user.
library;

import 'package:flutter/services.dart';

class BackgroundExecutionReadiness {
  const BackgroundExecutionReadiness({
    required this.notificationGranted,
    required this.exactAlarmAllowed,
    required this.batteryOptimizationIgnored,
    required this.autoStartGuidanceAvailable,
    required this.autoStartStatusKnown,
    required this.manufacturer,
    required this.bestEffort,
  });

  factory BackgroundExecutionReadiness.fromMap(Map<Object?, Object?> map) {
    return BackgroundExecutionReadiness(
      notificationGranted: map['notificationGranted'] == true,
      exactAlarmAllowed: map['exactAlarmAllowed'] == true,
      batteryOptimizationIgnored: map['batteryOptimizationIgnored'] == true,
      autoStartGuidanceAvailable: map['autoStartGuidanceAvailable'] == true,
      autoStartStatusKnown: map['autoStartStatusKnown'] == true,
      manufacturer: map['manufacturer'] as String? ?? 'Android',
      // Periodic work remains best-effort even with every permission enabled.
      bestEffort: map['bestEffort'] != false,
    );
  }

  factory BackgroundExecutionReadiness.conservative() {
    return const BackgroundExecutionReadiness(
      notificationGranted: false,
      exactAlarmAllowed: false,
      batteryOptimizationIgnored: false,
      autoStartGuidanceAvailable: false,
      autoStartStatusKnown: false,
      manufacturer: 'Android',
      bestEffort: true,
    );
  }

  final bool notificationGranted;
  final bool exactAlarmAllowed;
  final bool batteryOptimizationIgnored;
  final bool autoStartGuidanceAvailable;
  final bool autoStartStatusKnown;
  final String manufacturer;
  final bool bestEffort;

  bool get isFullyReady =>
      notificationGranted && exactAlarmAllowed && batteryOptimizationIgnored;
}

abstract final class BackgroundExecutionService {
  static const _channel = MethodChannel(
    'com.taworld.taworld/background_execution',
  );

  static Future<BackgroundExecutionReadiness> getReadiness() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getBackgroundReadiness',
      );
      if (result == null) return BackgroundExecutionReadiness.conservative();
      return BackgroundExecutionReadiness.fromMap(result);
    } on PlatformException {
      return BackgroundExecutionReadiness.conservative();
    } on MissingPluginException {
      return BackgroundExecutionReadiness.conservative();
    }
  }

  static Future<bool> openNotificationSettings() =>
      _open('openNotificationSettings');

  static Future<bool> openExactAlarmSettings() =>
      _open('openExactAlarmSettings');

  static Future<bool> openBatteryOptimizationSettings() =>
      _open('openBatteryOptimizationSettings');

  static Future<bool> openAutoStartSettings() => _open('openAutoStartSettings');

  static Future<bool> _open(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
