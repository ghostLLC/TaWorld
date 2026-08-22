/// Pure evaluation of forecast transitions for best-effort local monitoring.
library;

import 'package:timezone/timezone.dart' as tz;

import '../data/models/partner.dart';
import '../data/models/reminder_config.dart';
import 'weather_service.dart';

class WeatherAlertEvent {
  const WeatherAlertEvent({
    required this.condition,
    required this.eventTime,
    required this.eventKey,
    required this.message,
    required this.cooldown,
  });

  final String condition;
  final tz.TZDateTime eventTime;
  final String eventKey;
  final String message;
  final Duration cooldown;
}

/// Detects a meaningful change in the hourly forecast. It does not perform
/// network or persistence work, so background and foreground callers share
/// exactly the same decision rules.
abstract final class WeatherChangeMonitor {
  static WeatherAlertEvent? evaluate({
    required ReminderConfig config,
    required Partner partner,
    required FullWeatherResult weather,
    required DateTime nowUtc,
    required String deviceTimeZoneId,
  }) {
    if (!config.enabled || config.category != 'weather') return null;
    if (config.config['mode'] != 'weather_change') return null;

    final monitorLocation = _resolveLocation(
      config: config,
      partner: partner,
      deviceTimeZoneId: deviceTimeZoneId,
    );
    if (monitorLocation == null) return null;
    final sourceLocation = _locationOrNull(weather.sourceTimezoneId);
    if (sourceLocation == null) return null;

    final start = _parseClock(config.config['monitor_start']) ?? 7 * 60;
    final end = _parseClock(config.config['monitor_end']) ?? 23 * 60;
    final now = tz.TZDateTime.from(nowUtc.toUtc(), monitorLocation);
    if (!_isInWindow(now.hour * 60 + now.minute, start, end)) return null;

    final leadMinutes = _positiveInt(config.config['lead_minutes'], 180);
    final cooldownMinutes = _positiveInt(
      config.config['cooldown_minutes'],
      240,
    );
    final horizonUtc = nowUtc.toUtc().add(Duration(minutes: leadMinutes));
    final conditions = _stringList(config.config['notify_conditions'], const [
      'rain',
      'snow',
      'temperature_drop',
      'temperature_rise',
    ]);
    final points =
        _forecastPoints(weather, sourceLocation, monitorLocation)
            .where(
              (point) =>
                  point.time.toUtc().isAfter(nowUtc.toUtc()) &&
                  !point.time.toUtc().isAfter(horizonUtc) &&
                  _isInWindow(
                    point.time.hour * 60 + point.time.minute,
                    start,
                    end,
                  ),
            )
            .toList()
          ..sort((left, right) => left.time.compareTo(right.time));

    final currentRainy = _isRainy(weather.current.text);
    final currentSnowy = _isSnowy(weather.current.text);
    final rainChanceThreshold = _number(
      config.config['rain_probability_threshold'],
      60,
    );
    final precipitationThreshold = _number(
      config.config['precipitation_mm_threshold'],
      1,
    );
    final temperatureChangeThreshold = _number(
      config.config['temperature_change_threshold'],
      6,
    );
    final coldThreshold = _number(
      config.config['cold_temperature_threshold'],
      0,
    );
    final heatThreshold = _number(
      config.config['heat_temperature_threshold'],
      35,
    );

    for (final point in points) {
      for (final condition in conditions) {
        final message = switch (condition) {
          'rain'
              when !currentRainy &&
                  ((_isRainy(point.forecast.text) &&
                          point.forecast.chanceOfRain >= rainChanceThreshold) ||
                      point.forecast.precipMM >= precipitationThreshold) =>
            '${partner.nickname}那边${_leadLabel(nowUtc, point.time)}可能有${point.forecast.text}，提醒Ta带伞吧',
          'snow' when !currentSnowy && _isSnowy(point.forecast.text) =>
            '${partner.nickname}那边${_leadLabel(nowUtc, point.time)}可能有${point.forecast.text}，提醒Ta注意保暖',
          'temperature_drop'
              when weather.current.temp - point.forecast.temp >=
                  temperatureChangeThreshold =>
            '${partner.nickname}那边${_leadLabel(nowUtc, point.time)}可能降温到${point.forecast.temp}°C，提醒Ta添衣吧',
          'temperature_rise'
              when point.forecast.temp - weather.current.temp >=
                  temperatureChangeThreshold =>
            '${partner.nickname}那边${_leadLabel(nowUtc, point.time)}可能升温到${point.forecast.temp}°C，提醒Ta注意防晒补水',
          'extreme_cold'
              when weather.current.temp > coldThreshold &&
                  point.forecast.temp <= coldThreshold =>
            '${partner.nickname}那边${_leadLabel(nowUtc, point.time)}可能降到${point.forecast.temp}°C，提醒Ta注意保暖',
          'extreme_heat'
              when weather.current.temp < heatThreshold &&
                  point.forecast.temp >= heatThreshold =>
            '${partner.nickname}那边${_leadLabel(nowUtc, point.time)}可能升到${point.forecast.temp}°C，提醒Ta注意防暑',
          _ => null,
        };
        if (message == null) continue;

        final eventHourUtc = DateTime.utc(
          point.time.toUtc().year,
          point.time.toUtc().month,
          point.time.toUtc().day,
          point.time.toUtc().hour,
        );
        return WeatherAlertEvent(
          condition: condition,
          eventTime: point.time,
          eventKey:
              '${config.id}_${condition}_${eventHourUtc.millisecondsSinceEpoch}',
          message: message,
          cooldown: Duration(minutes: cooldownMinutes),
        );
      }
    }
    return null;
  }

  static tz.Location? _resolveLocation({
    required ReminderConfig config,
    required Partner partner,
    required String deviceTimeZoneId,
  }) {
    final monitorId = config.config['monitor_timezone_id'] as String?;
    final identifier = monitorId?.trim().isNotEmpty == true
        ? monitorId!.trim()
        : config.timezoneId?.trim().isNotEmpty == true
        ? config.timezoneId!.trim()
        : config.timezoneMode == 'partner'
        ? partner.timezoneConfirmed
              ? partner.timezoneId
              : null
        : deviceTimeZoneId;
    if (identifier == null || identifier.trim().isEmpty) return null;
    return _locationOrNull(identifier);
  }

  static tz.Location? _locationOrNull(String identifier) {
    try {
      return tz.getLocation(identifier);
    } catch (_) {
      return null;
    }
  }

  static List<_ForecastPoint> _forecastPoints(
    FullWeatherResult weather,
    tz.Location sourceLocation,
    tz.Location monitorLocation,
  ) {
    final result = <_ForecastPoint>[];
    for (final day in weather.forecast) {
      for (final hourly in day.hourly) {
        final date = DateTime.tryParse(hourly.date);
        if (date == null) continue;
        if (hourly.hour < 0 || hourly.hour > 23) continue;
        final sourceTime = tz.TZDateTime(
          sourceLocation,
          date.year,
          date.month,
          date.day,
          hourly.hour,
        );
        result.add(
          _ForecastPoint(
            forecast: hourly,
            time: tz.TZDateTime.from(sourceTime, monitorLocation),
          ),
        );
      }
    }
    return result;
  }

  static int? _parseClock(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static bool _isInWindow(int minute, int start, int end) {
    if (start == end) return true;
    if (start < end) return minute >= start && minute < end;
    return minute >= start || minute < end;
  }

  static int _positiveInt(Object? value, int fallback) {
    return value is int && value > 0 ? value : fallback;
  }

  static double _number(Object? value, num fallback) {
    return value is num ? value.toDouble() : fallback.toDouble();
  }

  static List<String> _stringList(Object? value, List<String> fallback) {
    if (value is! List) return fallback;
    final result = value.whereType<String>().toList();
    return result.isEmpty ? fallback : result;
  }

  static bool _isRainy(String text) {
    const keywords = ['雨', '雷阵雨', '冻雨', '雨夹雪'];
    return keywords.any(text.contains);
  }

  static bool _isSnowy(String text) {
    const keywords = ['雪', '雪粒', '阵雪', '雨夹雪'];
    return keywords.any(text.contains);
  }

  static String _leadLabel(DateTime nowUtc, tz.TZDateTime eventTime) {
    final minutes = eventTime.toUtc().difference(nowUtc.toUtc()).inMinutes;
    if (minutes < 60) return '不到一小时后';
    final hours = (minutes / 60).round();
    return '约$hours小时后';
  }
}

abstract final class WeatherAlertDeduplicator {
  static bool shouldNotify({
    required String eventKey,
    required DateTime nowUtc,
    required String? lastEventKey,
    required DateTime? lastNotifiedAt,
    required Duration cooldown,
  }) {
    if (lastEventKey == eventKey) return false;
    if (lastNotifiedAt == null) return true;
    return nowUtc.toUtc().difference(lastNotifiedAt.toUtc()) >= cooldown;
  }
}

class _ForecastPoint {
  const _ForecastPoint({required this.forecast, required this.time});

  final HourlyForecast forecast;
  final tz.TZDateTime time;
}
