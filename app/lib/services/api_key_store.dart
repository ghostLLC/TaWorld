import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ApiKeyStore {
  static const _key = 'deepseek_api_key';
  static const _storage = FlutterSecureStorage();
  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final stored = await _storage.read(key: _key);
      if (stored?.isNotEmpty == true) {
        if (prefs.containsKey(_key)) await prefs.remove(_key);
        return stored;
      }
      final legacy = prefs.getString(_key);
      if (legacy?.isNotEmpty == true) {
        await _storage.write(key: _key, value: legacy);
        if (await _storage.read(key: _key) == legacy) await prefs.remove(_key);
      }
      return legacy;
    } on MissingPluginException {
      // Read-only compatibility for unsupported hosts; never silently store new
      // credentials in plain preferences.
      return prefs.getString(_key);
    }
  }

  static Future<void> write(String value) async {
    if (value.trim().isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: _key, value: value.trim());
    if (await _storage.read(key: _key) != value.trim()) {
      throw StateError('密钥保存未完成');
    }
    await (await SharedPreferences.getInstance()).remove(_key);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _key);
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
