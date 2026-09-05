/// TaWorld 天气服务 — 使用 Open-Meteo 免费 API
///
/// Open-Meteo 基于 ECMWF / GFS 气象模型数据，完全免费、无需 API Key。
/// 支持当前天气 + 7 天逐日预报。
/// 国内网络可正常访问（api.open-meteo.com）。
///
/// API 文档：https://open-meteo.com/en/docs
library;

import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';

import 'stale_while_revalidate_cache.dart';
import '../data/city_coordinates.dart';

// ==================== 城市坐标映射 ====================

/// 城市中文名 → [纬度, 经度]
/// 覆盖所有中国地级市 + 港澳台 + 主要海外城市（约 410 个）

// ==================== 数据模型 ====================

/// 天气查询结果
class WeatherResult {
  final String text; // 天气描述（中文）
  final int temp; // 温度（°C）
  final String? windDir; // 风向
  final int? humidity; // 湿度（%）
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
  final String date; // yyyy-MM-dd in the forecast location
  final int hour; // 0-23
  final String text; // 天气描述（中文）
  final int temp; // 温度（°C）
  final int chanceOfRain; // 降水概率（%）
  final double precipMM; // 降水量（mm）
  const HourlyForecast({
    required this.date,
    required this.hour,
    required this.text,
    required this.temp,
    required this.chanceOfRain,
    required this.precipMM,
  });
}

/// 每日预报
class DailyForecast {
  final String date; // yyyy-MM-dd
  final int maxTemp; // 最高温（°C）
  final int minTemp; // 最低温（°C）
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

  /// IANA timezone used by the provider for local forecast wall-clock values.
  final String sourceTimezoneId;
  final List<DailyForecast> forecast; // 最多 3 天
  const FullWeatherResult({
    required this.current,
    required this.sourceTimezoneId,
    required this.forecast,
  });
}

// ==================== 天气服务 ====================

abstract final class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const cacheTtl = Duration(minutes: 10);
  static final StaleWhileRevalidateCache<String, FullWeatherResult>
  _fullWeatherCache = StaleWhileRevalidateCache(ttl: cacheTtl);

  /// 最后一次查询失败的原因（中文，可直接展示给用户）
  static String? lastError;

  /// Parses Open-Meteo data while preserving the timezone in which its
  /// timezone-less hourly strings must be interpreted.
  static FullWeatherResult parseOpenMeteoResponse(Map<String, dynamic> data) {
    final sourceTimezoneId = data['timezone'];
    if (sourceTimezoneId is! String || sourceTimezoneId.trim().isEmpty) {
      throw const FormatException('天气数据缺少来源时区');
    }

    final current = data['current'] as Map<String, dynamic>?;
    if (current == null) throw const FormatException('天气数据格式异常');

    final weatherCode = current['weather_code'] as int? ?? 0;
    final currentWeather = WeatherResult(
      text: _wmoToChinese(weatherCode),
      temp: (current['temperature_2m'] as num?)?.round() ?? 0,
      humidity: (current['relative_humidity_2m'] as num?)?.round(),
      windDir: _windDegToChinese(
        (current['wind_direction_10m'] as num?)?.toDouble() ?? 0,
      ),
    );

    final daily = data['daily'] as Map<String, dynamic>?;
    final hourly = data['hourly'] as Map<String, dynamic>?;
    final forecast = <DailyForecast>[];

    if (daily != null) {
      final dates = (daily['time'] as List?)?.cast<String>() ?? [];
      final maxTemps =
          (daily['temperature_2m_max'] as List?)?.cast<num>() ?? [];
      final minTemps =
          (daily['temperature_2m_min'] as List?)?.cast<num>() ?? [];
      final hourlyTimes = (hourly?['time'] as List?)?.cast<String>() ?? [];
      final hourlyTemps =
          (hourly?['temperature_2m'] as List?)?.cast<num>() ?? [];
      final hourlyCodes = (hourly?['weather_code'] as List?)?.cast<int>() ?? [];
      final hourlyPrecipProb =
          (hourly?['precipitation_probability'] as List?)?.cast<num>() ?? [];
      final hourlyPrecip =
          (hourly?['precipitation'] as List?)?.cast<num>() ?? [];

      for (var dayIndex = 0; dayIndex < dates.length; dayIndex++) {
        final datePrefix = dates[dayIndex];
        final hourlyForecasts = <HourlyForecast>[];

        for (var hourIndex = 0; hourIndex < hourlyTimes.length; hourIndex++) {
          final timestamp = hourlyTimes[hourIndex];
          if (!timestamp.startsWith(datePrefix) || timestamp.length < 13) {
            continue;
          }
          final hour = int.tryParse(timestamp.substring(11, 13));
          if (hour == null || hour < 0 || hour > 23) continue;
          hourlyForecasts.add(
            HourlyForecast(
              date: datePrefix,
              hour: hour,
              text: _wmoToChinese(
                hourIndex < hourlyCodes.length ? hourlyCodes[hourIndex] : 0,
              ),
              temp:
                  (hourIndex < hourlyTemps.length ? hourlyTemps[hourIndex] : 0)
                      .round(),
              chanceOfRain:
                  (hourIndex < hourlyPrecipProb.length
                          ? hourlyPrecipProb[hourIndex]
                          : 0)
                      .round(),
              precipMM:
                  (hourIndex < hourlyPrecip.length
                          ? hourlyPrecip[hourIndex]
                          : 0)
                      .toDouble(),
            ),
          );
        }

        forecast.add(
          DailyForecast(
            date: datePrefix,
            maxTemp: (dayIndex < maxTemps.length ? maxTemps[dayIndex] : 0)
                .round(),
            minTemp: (dayIndex < minTemps.length ? minTemps[dayIndex] : 0)
                .round(),
            hourly: hourlyForecasts,
          ),
        );
      }
    }

    return FullWeatherResult(
      current: currentWeather,
      sourceTimezoneId: sourceTimezoneId.trim(),
      forecast: forecast,
    );
  }

  // ==================== 天气查询 ====================

  /// 获取当前天气（经纬度）
  static Future<WeatherResult?> getCurrentWeather(
    double longitude,
    double latitude,
  ) async {
    lastError = null;
    final full = await getFullWeatherByCoords(latitude, longitude);
    return full?.current;
  }

  /// 获取当前天气（城市名）
  static Future<WeatherResult?> getCurrentWeatherByCity(String city) async {
    lastError = null;
    final full = await getFullWeather(city);
    return full?.current;
  }

  /// 获取完整天气数据（城市名，当前 + 3 天预报）
  static Future<FullWeatherResult?> getFullWeather(
    String location, {
    bool forceRefresh = false,
  }) {
    lastError = null;
    final cacheKey = 'location:${location.trim().toLowerCase()}';
    Future<FullWeatherResult?> loader() => _loadFullWeather(location);
    return forceRefresh
        ? _fullWeatherCache.refresh(cacheKey, loader)
        : _fullWeatherCache.get(cacheKey, loader);
  }

  static Future<FullWeatherResult?> _loadFullWeather(String location) async {
    // 0. 清理城市名：去空格、去掉"市"/"县"/"区"后缀
    final cleaned = location.trim().replaceAll(RegExp(r'[市县区]$'), '');

    // 1. 先查坐标映射表（用清理后的名字）
    final coords = kCityCoordinates[cleaned];
    if (coords != null) {
      return _loadFullWeatherByCoords(coords[0], coords[1]);
    }

    // 1b. 也尝试原始名字（以防万一）
    if (cleaned != location.trim()) {
      final coords2 = kCityCoordinates[location.trim()];
      if (coords2 != null) {
        return _loadFullWeatherByCoords(coords2[0], coords2[1]);
      }
    }

    // 2. 如果 location 本身是 "纬度,经度" 格式
    if (location.contains(',')) {
      final parts = location.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lon = double.tryParse(parts[1].trim());
        if (lat != null && lon != null) {
          return _loadFullWeatherByCoords(lat, lon);
        }
      }
    }

    // 3. 通过 geocoding 将城市名转为坐标（用清理后的名字）
    try {
      final locations = await locationFromAddress(
        cleaned,
      ).timeout(const Duration(seconds: 8));
      if (locations.isNotEmpty) {
        return _loadFullWeatherByCoords(
          locations.first.latitude,
          locations.first.longitude,
        );
      }
    } catch (e) {
      lastError = '城市定位失败：$e';
    }

    lastError ??= '找不到城市「$cleaned」的坐标';
    return null;
  }

  /// 获取完整天气数据（坐标，当前 + 3 天预报）
  static Future<FullWeatherResult?> getFullWeatherByCoords(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
  }) {
    lastError = null;
    final cacheKey =
        'coords:${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    Future<FullWeatherResult?> loader() =>
        _loadFullWeatherByCoords(latitude, longitude);
    return forceRefresh
        ? _fullWeatherCache.refresh(cacheKey, loader)
        : _fullWeatherCache.get(cacheKey, loader);
  }

  static Future<FullWeatherResult?> _loadFullWeatherByCoords(
    double latitude,
    double longitude,
  ) async {
    final dio = Dio();
    try {
      final response = await dio.get(
        _baseUrl,
        queryParameters: {
          'latitude': latitude,
          'longitude': longitude,
          'current':
              'temperature_2m,relative_humidity_2m,weather_code,wind_direction_10m',
          'hourly':
              'temperature_2m,weather_code,precipitation_probability,precipitation',
          'daily':
              'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum',
          'timezone': 'auto',
          'forecast_days': 3,
        },
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      final data = response.data;
      if (data == null) {
        lastError = '天气服务返回空数据';
        return null;
      }

      if (data is! Map) {
        lastError = '天气数据格式异常';
        return null;
      }
      return parseOpenMeteoResponse(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
          lastError = '天气查询连接超时，请检查网络';
        case DioExceptionType.receiveTimeout:
          lastError = '天气数据接收超时，请稍后重试';
        case DioExceptionType.connectionError:
          lastError = '无法连接天气服务，请检查网络连接';
        case DioExceptionType.badResponse:
          lastError = '天气服务响应异常（${e.response?.statusCode}）';
        default:
          lastError = '天气查询失败：${e.message ?? "未知网络错误"}';
      }
      return null;
    } catch (e) {
      lastError = '天气查询出错：$e';
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
              message: 'Ta那边要${weather.text}了，提醒Ta带伞吧',
            );
          }
        case 'snow':
          if (_isSnowy(weather.text)) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'snow',
              message: 'Ta那边要${weather.text}啦，提醒Ta注意保暖',
            );
          }
        case 'extreme_cold':
          if (weather.temp <= 0) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'extreme_cold',
              message: 'Ta那边好冷啊（${weather.temp}°C），提醒Ta多穿点',
            );
          }
        case 'extreme_heat':
          if (weather.temp >= 35) {
            return WeatherCheckResult(
              shouldRemind: true,
              condition: 'extreme_heat',
              message: 'Ta那边好热啊（${weather.temp}°C），提醒Ta注意防暑',
            );
          }
      }
    }
    return const WeatherCheckResult(shouldRemind: false);
  }

  static bool _isRainy(String text) {
    const keywords = [
      '小雨',
      '中雨',
      '大雨',
      '暴雨',
      '阵雨',
      '雷阵雨',
      '毛毛雨',
      '冻雨',
      '雨夹雪',
      '细雨',
    ];
    return keywords.any(text.contains);
  }

  static bool _isSnowy(String text) {
    const keywords = ['小雪', '中雪', '大雪', '暴雪', '雪粒', '阵雪', '雨夹雪'];
    return keywords.any(text.contains);
  }

  // ==================== WMO 天气代码 → 中文 ====================

  /// WMO Weather interpretation codes (WMO Code Table 4677)
  /// 参考：https://open-meteo.com/en/docs
  static String _wmoToChinese(int code) {
    return switch (code) {
      0 => '晴',
      1 => '晴', // Mainly clear
      2 => '多云', // Partly cloudy
      3 => '阴', // Overcast
      45 => '雾', // Fog
      48 => '雾凇', // Depositing rime fog
      51 => '毛毛雨', // Light drizzle
      53 => '毛毛雨', // Moderate drizzle
      55 => '细雨', // Dense drizzle
      56 => '冻毛毛雨', // Light freezing drizzle
      57 => '冻毛毛雨', // Dense freezing drizzle
      61 => '小雨', // Slight rain
      63 => '中雨', // Moderate rain
      65 => '大雨', // Heavy rain
      66 => '冻雨', // Light freezing rain
      67 => '冻雨', // Heavy freezing rain
      71 => '小雪', // Slight snow
      73 => '中雪', // Moderate snow
      75 => '大雪', // Heavy snow
      77 => '雪粒', // Snow grains
      80 => '阵雨', // Slight rain showers
      81 => '阵雨', // Moderate rain showers
      82 => '暴雨', // Violent rain showers
      85 => '阵雪', // Slight snow showers
      86 => '阵雪', // Heavy snow showers
      95 => '雷阵雨', // Thunderstorm
      96 => '雷阵雨', // Thunderstorm with slight hail
      99 => '雷阵雨', // Thunderstorm with heavy hail
      _ => '未知',
    };
  }

  // ==================== 风向转换 ====================

  /// 风向角度（0-360°）→ 中文方位
  static String _windDegToChinese(double deg) {
    if (deg < 0) return '';
    // 16 方位，每个 22.5°
    final normalized = deg % 360;
    if (normalized >= 348.75 || normalized < 11.25) return '北风';
    if (normalized < 33.75) return '东北风';
    if (normalized < 56.25) return '东北风';
    if (normalized < 78.75) return '东风';
    if (normalized < 101.25) return '东风';
    if (normalized < 123.75) return '东南风';
    if (normalized < 146.25) return '东南风';
    if (normalized < 168.75) return '南风';
    if (normalized < 191.25) return '南风';
    if (normalized < 213.75) return '西南风';
    if (normalized < 236.25) return '西南风';
    if (normalized < 258.75) return '西风';
    if (normalized < 281.25) return '西风';
    if (normalized < 303.75) return '西北风';
    if (normalized < 326.25) return '西北风';
    return '北风';
  }
}
