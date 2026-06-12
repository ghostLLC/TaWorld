/// TaWorld 主题服务
///
/// 管理暗色模式切换和推送通知开关，持久化到 SharedPreferences。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._();
  ThemeService._();

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool _pushEnabled = true;
  bool get pushEnabled => _pushEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final themeVal = prefs.getString('theme_mode') ?? 'system';
    _mode = switch (themeVal) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _pushEnabled = prefs.getBool('push_enabled') ?? true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', dark ? 'dark' : 'light');
  }

  /// 设置主题模式（支持跟随系统）
  Future<void> setThemeMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('theme_mode', value);
  }

  Future<void> setPushEnabled(bool enabled) async {
    _pushEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_enabled', enabled);
  }
}
