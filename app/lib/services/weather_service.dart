/// TaWorld 天气服务 — 直连和风天气 API
///
/// 和风天气开发版 API，免费额度每日 1000 次调用。
library;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 天气查询结果
class WeatherResult {
  final String text;       // 天气描述
  final int temp;          // 温度
  final String? windDir;   // 风向
  final int? humidity;     // 湿度
  const WeatherResult({
    required this.text,
    required this.temp,
    this.windDir,
    this.humidity,
  });
}

/// 天气条件检查结果
class WeatherCheckResult {
  final bool shouldRemind;
  final String? condition;
  final String? message;
  const WeatherCheckResult({
    required this.shouldRemind,
    this.condition,
    this.message,
  });
}

abstract final class WeatherService {
  static const _baseUrl = 'https://devapi.qweather.com/v7';

  // ==================== API Key 管理 ====================

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('qweather_api_key');
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('qweather_api_key', key);
  }

  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  // ==================== 天气查询 ====================

  /// 获取当前天气
  static Future<WeatherResult?> getCurrentWeather(
    double longitude,
    double latitude,
  ) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return null;

    try {
      final dio = Dio();
      final response = await dio.get(
        '$_baseUrl/weather/now',
        queryParameters: {
          'location': '$longitude,$latitude',
          'key': key,
        },
      );

      if (response.data['code'] == '200') {
        final now = response.data['now'] as Map<String, dynamic>;
        return WeatherResult(
          text: now['text'] as String? ?? '未知',
          temp: int.tryParse(now['temp']?.toString() ?? '0') ?? 0,
          windDir: now['windDir'] as String?,
          humidity: int.tryParse(now['humidity']?.toString() ?? '0'),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 检查天气是否满足提醒条件
  static WeatherCheckResult checkConditions(
    WeatherResult weather,
    List<String> conditions,
  ) {
    for (final condition in conditions) {
      switch (condition) {
        case 'rain':
          if (_isRainy(weather.text)) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'rain',
              message: 'Ta那边要${weather.text}了，提醒Ta带伞吧 🌂',
            );
          }
        case 'snow':
          if (_isSnowy(weather.text)) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'snow',
              message: 'Ta那边要${weather.text}啦，提醒Ta注意保暖 ❄️',
            );
          }
        case 'extreme_cold':
          if (weather.temp <= 0) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'extreme_cold',
              message: 'Ta那边好冷啊（${weather.temp}°C），提醒Ta多穿点 🧣',
            );
          }
        case 'extreme_heat':
          if (weather.temp >= 35) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'extreme_heat',
              message: 'Ta那边好热啊（${weather.temp}°C），提醒Ta注意防暑 🧊',
            );
          }
      }
    }
    return const WeatherCheckResult(shouldRemind: false);
  }

  static bool _isRainy(String text) {
    const keywords = ['小雨', '中雨', '大雨', '暴雨', '阵雨', '雷阵雨'];
    return keywords.any(text.contains);
  }

  static bool _isSnowy(String text) {
    const keywords = ['小雪', '中雪', '大雪', '暴雪', '雨夹雪'];
    return keywords.any(text.contains);
  }
}
