/// TaWorld 天气服务 — 使用 wttr.in 免费 API
///
/// wttr.in 基于 WorldWeatherOnline 数据，完全免费、无需 API Key。
/// 支持当前天气 + 3 天逐时预报（含降水概率）。
/// 国内网络可正常访问。
///
/// API 文档：https://wttr.in/:help
library;

import 'package:dio/dio.dart';

/// 天气查询结果
class WeatherResult {
  final String text;       // 天气描述（中文）
  final int temp;          // 温度（°C）
  final String? windDir;   // 风向
  final int? humidity;     // 湿度（%）
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

/// 逐时预报项
class HourlyForecast {
  final int hour;           // 0-23
  final String text;        // 天气描述（中文）
  final int temp;           // 温度（°C）
  final int chanceOfRain;   // 降水概率（%）
  final double precipMM;    // 降水量（mm）
  const HourlyForecast({
    required this.hour,
    required this.text,
    required this.temp,
    required this.chanceOfRain,
    required this.precipMM,
  });
}

/// 每日预报
class DailyForecast {
  final String date;              // yyyy-MM-dd
  final int maxTemp;              // 最高温（°C）
  final int minTemp;              // 最低温（°C）
  final List<HourlyForecast> hourly;
  const DailyForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.hourly,
  });
}

/// 完整天气查询结果（当前 + 预报）
class FullWeatherResult {
  final WeatherResult current;
  final List<DailyForecast> forecast; // 最多 3 天
  const FullWeatherResult({
    required this.current,
    required this.forecast,
  });
}

abstract final class WeatherService {
  static const _baseUrl = 'https://wttr.in';

  // ==================== 天气查询 ====================

  /// 获取当前天气（经纬度）
  static Future<WeatherResult?> getCurrentWeather(
    double longitude,
    double latitude,
  ) async {
    final full = await getFullWeather('$latitude,$longitude');
    return full?.current;
  }

  /// 获取当前天气（城市名）
  static Future<WeatherResult?> getCurrentWeatherByCity(String city) async {
    final full = await getFullWeather(city);
    return full?.current;
  }

  /// 获取完整天气数据（当前 + 3 天预报）
  /// [location] 可以是城市名或 "纬度,经度"
  static Future<FullWeatherResult?> getFullWeather(String location) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        '$_baseUrl/$location',
        queryParameters: {
          'format': 'j1',
          'lang': 'zh',
        },
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      final data = response.data;
      if (data == null) return null;

      // ---------- 当前天气 ----------
      final currentList = data['current_condition'] as List?;
      if (currentList == null || currentList.isEmpty) return null;

      final cc = currentList[0] as Map<String, dynamic>;
      final currentDesc = _extractDescription(cc);
      final current = WeatherResult(
        text: _translateToChinese(currentDesc),
        temp: int.tryParse(cc['temp_C']?.toString() ?? '') ?? 0,
        humidity: int.tryParse(cc['humidity']?.toString() ?? ''),
        windDir: _windDir16ToChinese(cc['winddir16Point']?.toString() ?? ''),
      );

      // ---------- 3 天预报 ----------
      final weatherList = data['weather'] as List? ?? [];
      final forecast = <DailyForecast>[];

      for (final dayData in weatherList) {
        final day = dayData as Map<String, dynamic>;
        final date = day['date']?.toString() ?? '';
        final maxTemp = int.tryParse(day['maxtempC']?.toString() ?? '') ?? 0;
        final minTemp = int.tryParse(day['mintempC']?.toString() ?? '') ?? 0;

        final hourlyList = day['hourly'] as List? ?? [];
        final hourly = <HourlyForecast>[];

        for (final hData in hourlyList) {
          final h = hData as Map<String, dynamic>;
          final timeStr = h['time']?.toString() ?? '0';
          final hour = (int.tryParse(timeStr) ?? 0) ~/ 100;
          final hDesc = _extractDescription(h);

          hourly.add(HourlyForecast(
            hour: hour,
            text: _translateToChinese(hDesc),
            temp: int.tryParse(h['tempC']?.toString() ?? '') ?? 0,
            chanceOfRain:
                int.tryParse(h['chanceofrain']?.toString() ?? '') ?? 0,
            precipMM:
                double.tryParse(h['precipMM']?.toString() ?? '') ?? 0.0,
          ));
        }

        forecast.add(DailyForecast(
          date: date,
          maxTemp: maxTemp,
          minTemp: minTemp,
          hourly: hourly,
        ));
      }

      return FullWeatherResult(current: current, forecast: forecast);
    } catch (_) {
      return null;
    }
  }

  // ==================== 天气条件检查 ====================

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
    const keywords = ['小雨', '中雨', '大雨', '暴雨', '阵雨', '雷阵雨', '毛毛雨', '冻雨', '雨夹雪'];
    return keywords.any(text.contains);
  }

  static bool _isSnowy(String text) {
    const keywords = ['小雪', '中雪', '大雪', '暴雪', '雪粒', '阵雪', '雨夹雪'];
    return keywords.any(text.contains);
  }

  // ==================== 辅助方法 ====================

  /// 从 wttr.in JSON 节点提取英文天气描述
  static String _extractDescription(Map<String, dynamic> node) {
    // 优先取 weatherDesc
    final desc = node['weatherDesc'] as List?;
    if (desc != null && desc.isNotEmpty) {
      final first = desc[0] as Map<String, dynamic>;
      return (first['value'] as String?)?.trim() ?? '';
    }
    return '';
  }

  /// 风向 16 方位英文 → 中文
  static String _windDir16ToChinese(String dir) {
    return switch (dir.trim().toUpperCase()) {
      'N' || 'NNE' || 'NNW' => '北风',
      'NE' || 'ENE' => '东北风',
      'E' || 'ESE' => '东风',
      'SE' || 'SSE' => '东南风',
      'S' || 'SSW' => '南风',
      'SW' || 'WSW' => '西南风',
      'W' || 'WNW' => '西风',
      'NW' => '西北风',
      _ => '',
    };
  }

  /// wttr.in 英文天气描述 → 中文
  /// 参考：WorldWeatherOnline weather descriptions
  static String _translateToChinese(String desc) {
    final normalized = desc.trim();

    // 精确匹配优先
    final exact = _descMap[normalized];
    if (exact != null) return exact;

    // 忽略大小写匹配
    final lower = normalized.toLowerCase();
    for (final entry in _descMap.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }

    // 关键词兜底
    if (lower.contains('thunderstorm')) return '雷阵雨';
    if (lower.contains('heavy snow') || lower.contains('blizzard')) return '暴雪';
    if (lower.contains('heavy rain') || lower.contains('torrential')) return '暴雨';
    if (lower.contains('moderate snow')) return '中雪';
    if (lower.contains('moderate rain')) return '中雨';
    if (lower.contains('light snow') || lower.contains('snow shower')) return '小雪';
    if (lower.contains('light rain') || lower.contains('rain shower')) return '小雨';
    if (lower.contains('drizzle')) return '毛毛雨';
    if (lower.contains('snow')) return '雪';
    if (lower.contains('rain')) return '雨';
    if (lower.contains('fog') || lower.contains('mist')) return '雾';
    if (lower.contains('haze') || lower.contains('smoke')) return '霾';
    if (lower.contains('cloudy') || lower.contains('overcast')) return '多云';
    if (lower.contains('partly')) return '多云';
    if (lower.contains('clear') || lower.contains('sunny')) return '晴';

    return '未知';
  }

  /// wttr.in 天气描述 → 中文映射表
  static const _descMap = <String, String>{
    'Sunny': '晴',
    'Clear': '晴',
    'Clear ': '晴',
    'Partly Cloudy': '多云',
    'Partly Cloudy ': '多云',
    'Partly cloudy': '多云',
    'Cloudy': '多云',
    'Overcast': '阴',
    'Mist': '薄雾',
    'Fog': '雾',
    'Freezing fog': '冻雾',
    'Patchy rain possible': '局部有雨',
    'Patchy rain nearby': '局部小雨',
    'Patchy rain': '局部小雨',
    'Patchy snow possible': '局部有雪',
    'Patchy snow nearby': '局部小雪',
    'Patchy sleet possible': '局部有雨夹雪',
    'Patchy sleet nearby': '局部雨夹雪',
    'Patchy freezing drizzle possible': '局部冻毛毛雨',
    'Patchy freezing drizzle nearby': '局部冻毛毛雨',
    'Thundery outbreaks possible': '可能有雷阵雨',
    'Thundery outbreaks in nearby': '附近有雷阵雨',
    'Blowing snow': '吹雪',
    'Blizzard': '暴风雪',
    'Light drizzle': '毛毛雨',
    'Patchy light drizzle': '局部毛毛雨',
    'Freezing drizzle': '冻毛毛雨',
    'Heavy freezing drizzle': '强冻毛毛雨',
    'Patchy light rain': '局部小雨',
    'Light rain': '小雨',
    'Light rain shower': '小阵雨',
    'Moderate rain at times': '时有中雨',
    'Moderate rain': '中雨',
    'Heavy rain at times': '时有大雨',
    'Heavy rain': '大雨',
    'Light freezing rain': '小冻雨',
    'Moderate or heavy freezing rain': '中到大冻雨',
    'Light sleet': '小雨夹雪',
    'Moderate or heavy sleet': '中到大雨夹雪',
    'Patchy light snow': '局部小雪',
    'Light snow': '小雪',
    'Patchy moderate snow': '局部中雪',
    'Moderate snow': '中雪',
    'Patchy heavy snow': '局部大雪',
    'Heavy snow': '大雪',
    'Ice pellets': '冰粒',
    'Moderate or heavy rain shower': '中到大阵雨',
    'Torrential rain shower': '暴雨',
    'Light sleet showers': '小雨夹雪阵雨',
    'Moderate or heavy sleet showers': '中到大雨夹雪阵雨',
    'Light snow showers': '小阵雪',
    'Moderate or heavy snow showers': '中到大阵雪',
    'Light showers of ice pellets': '小冰粒阵雨',
    'Moderate or heavy showers of ice pellets': '中到大冰粒阵雨',
    'Patchy light rain with thunder': '局部雷阵雨',
    'Moderate or heavy rain with thunder': '中到大雷阵雨',
    'Patchy light snow with thunder': '局部雷阵雪',
    'Moderate or heavy snow with thunder': '中到大雷阵雪',
    'Smoky haze': '霾',
    'Haze': '霾',
    'Widespread dust': '扬沙',
    'Sand': '沙尘',
    'Volcanic ash': '火山灰',
  };
}
