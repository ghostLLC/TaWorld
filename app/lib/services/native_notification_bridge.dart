import 'package:flutter/services.dart';

abstract final class NativeNotificationBridge {
  static const channel = MethodChannel(
    'com.taworld.taworld/notification_ledger',
  );
  static Future<T?> invoke<T>(String method, [Object? arguments]) async {
    try {
      return await channel
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(seconds: 5));
    } on MissingPluginException {
      // Non-Android platforms and unit tests use flutter_local_notifications.
      return null;
    }
  }

  static Future<List<Map<String, Object?>>?> records(String method) async {
    final rows = await invoke<List<dynamic>>(method);
    return rows?.map((row) => Map<String, Object?>.from(row as Map)).toList();
  }
}
