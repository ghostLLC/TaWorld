import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/data/models/reminder_config.dart';
import 'package:taworld/services/weather_change_monitor.dart';
import 'package:taworld/services/weather_service.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  final timestamp = DateTime.utc(2026, 1, 1);

  Partner partner({
    String? timezoneId = 'Asia/Singapore',
    bool? timezoneConfirmed,
  }) => Partner(
    id: 'partner-1',
    nickname: '小乐',
    type: 'friend',
    timezoneId: timezoneId,
    timezoneConfirmed: timezoneConfirmed ?? timezoneId != null,
    status: 'active',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  ReminderConfig config({
    Map<String, dynamic> values = const {},
    String timezoneMode = 'partner',
  }) {
    return ReminderConfig(
      id: 'config-1',
      partnerId: 'partner-1',
      category: 'weather',
      enabled: true,
      config: {
        'mode': 'weather_change',
        'monitor_start': '07:00',
        'monitor_end': '23:00',
        'lead_minutes': 180,
        'cooldown_minutes': 240,
        'notify_conditions': ['rain', 'temperature_drop'],
        'rain_probability_threshold': 60,
        'precipitation_mm_threshold': 1.0,
        'temperature_change_threshold': 6,
        ...values,
      },
      timezoneMode: timezoneMode,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  FullWeatherResult weather({
    String currentText = '多云',
    int currentTemp = 30,
    String sourceTimezoneId = 'Asia/Singapore',
    required List<HourlyForecast> hourly,
  }) {
    final byDate = <String, List<HourlyForecast>>{};
    for (final item in hourly) {
      byDate.putIfAbsent(item.date, () => []).add(item);
    }
    return FullWeatherResult(
      current: WeatherResult(text: currentText, temp: currentTemp),
      sourceTimezoneId: sourceTimezoneId,
      forecast: byDate.entries
          .map(
            (entry) => DailyForecast(
              date: entry.key,
              maxTemp: entry.value
                  .map((item) => item.temp)
                  .reduce((left, right) => left > right ? left : right),
              minTemp: entry.value
                  .map((item) => item.temp)
                  .reduce((left, right) => left < right ? left : right),
              hourly: entry.value,
            ),
          )
          .toList(),
    );
  }

  HourlyForecast point(
    String date,
    int hour, {
    String text = '多云',
    int temp = 30,
    int rainChance = 0,
    double precipitation = 0,
  }) {
    return HourlyForecast(
      date: date,
      hour: hour,
      text: text,
      temp: temp,
      chanceOfRain: rainChance,
      precipMM: precipitation,
    );
  }

  test('detects an upcoming rain transition inside lead time and window', () {
    final event = WeatherChangeMonitor.evaluate(
      config: config(),
      partner: partner(),
      weather: weather(
        hourly: [
          point('2026-08-22', 10),
          point(
            '2026-08-22',
            11,
            text: '大雨',
            temp: 27,
            rainChance: 85,
            precipitation: 4.2,
          ),
        ],
      ),
      nowUtc: DateTime.utc(2026, 8, 22, 2), // Singapore 10:00
      deviceTimeZoneId: 'Asia/Shanghai',
    );

    expect(event?.condition, 'rain');
    expect(event?.eventTime.toUtc(), DateTime.utc(2026, 8, 22, 3));
    expect(event?.message, contains('小乐'));
    expect(event?.message, contains('大雨'));
    expect(event?.eventKey, contains('config-1_rain_'));
  });

  test('does not report rain when it is already raining now', () {
    final event = WeatherChangeMonitor.evaluate(
      config: config(),
      partner: partner(),
      weather: weather(
        currentText: '中雨',
        hourly: [
          point('2026-08-22', 11, text: '大雨', rainChance: 90, precipitation: 5),
        ],
      ),
      nowUtc: DateTime.utc(2026, 8, 22, 2),
      deviceTimeZoneId: 'Asia/Shanghai',
    );

    expect(event, isNull);
  });

  test('honors monitoring window and forecast lead time', () {
    final outsideWindow = WeatherChangeMonitor.evaluate(
      config: config(),
      partner: partner(),
      weather: weather(
        hourly: [
          point('2026-08-22', 5, text: '大雨', rainChance: 90, precipitation: 5),
        ],
      ),
      nowUtc: DateTime.utc(2026, 8, 21, 20), // Singapore 04:00
      deviceTimeZoneId: 'Asia/Shanghai',
    );
    final beyondLead = WeatherChangeMonitor.evaluate(
      config: config(values: const {'lead_minutes': 60}),
      partner: partner(),
      weather: weather(
        hourly: [
          point('2026-08-22', 13, text: '大雨', rainChance: 90, precipitation: 5),
        ],
      ),
      nowUtc: DateTime.utc(2026, 8, 22, 2), // Singapore 10:00
      deviceTimeZoneId: 'Asia/Shanghai',
    );

    expect(outsideWindow, isNull);
    expect(beyondLead, isNull);
  });

  test('supports an overnight monitoring window', () {
    final event = WeatherChangeMonitor.evaluate(
      config: config(
        values: const {'monitor_start': '22:00', 'monitor_end': '07:00'},
      ),
      partner: partner(),
      weather: weather(
        hourly: [
          point('2026-08-23', 1, text: '大雨', rainChance: 90, precipitation: 5),
        ],
      ),
      nowUtc: DateTime.utc(2026, 8, 22, 16), // Singapore 00:00
      deviceTimeZoneId: 'Asia/Shanghai',
    );

    expect(event?.condition, 'rain');
  });

  test('does not use an unconfirmed partner timezone as a fallback', () {
    final event = WeatherChangeMonitor.evaluate(
      config: config(),
      partner: partner(timezoneConfirmed: false),
      weather: weather(
        hourly: [
          point('2026-08-22', 11, text: '大雨', rainChance: 90, precipitation: 5),
        ],
      ),
      nowUtc: DateTime.utc(2026, 8, 22, 2),
      deviceTimeZoneId: 'Asia/Shanghai',
    );

    expect(event, isNull);
  });

  test(
    'interprets forecast wall time in its source zone before monitor conversion',
    () {
      final event = WeatherChangeMonitor.evaluate(
        config: config(
          timezoneMode: 'user',
          values: const {
            'monitor_start': '00:00',
            'monitor_end': '04:00',
            'lead_minutes': 180,
          },
        ),
        partner: partner(),
        weather: weather(
          sourceTimezoneId: 'America/Los_Angeles',
          hourly: [
            point(
              '2026-08-22',
              11,
              text: '大雨',
              rainChance: 90,
              precipitation: 5,
            ),
          ],
        ),
        nowUtc: DateTime.utc(2026, 8, 22, 17),
        deviceTimeZoneId: 'Asia/Shanghai',
      );

      expect(event?.condition, 'rain');
      expect(event?.eventTime.toUtc(), DateTime.utc(2026, 8, 22, 18));
      expect(event?.eventTime.hour, 2); // 02:00 next day in Shanghai.
    },
  );

  test(
    'detects a temperature drop only at or beyond the configured threshold',
    () {
      final belowThreshold = WeatherChangeMonitor.evaluate(
        config: config(),
        partner: partner(),
        weather: weather(
          currentTemp: 30,
          hourly: [point('2026-08-22', 11, temp: 25)],
        ),
        nowUtc: DateTime.utc(2026, 8, 22, 2),
        deviceTimeZoneId: 'Asia/Shanghai',
      );
      final atThreshold = WeatherChangeMonitor.evaluate(
        config: config(),
        partner: partner(),
        weather: weather(
          currentTemp: 30,
          hourly: [point('2026-08-22', 11, temp: 24)],
        ),
        nowUtc: DateTime.utc(2026, 8, 22, 2),
        deviceTimeZoneId: 'Asia/Shanghai',
      );

      expect(belowThreshold, isNull);
      expect(atThreshold?.condition, 'temperature_drop');
    },
  );

  test(
    'event dedupe blocks the same event and cooldown blocks nearby events',
    () {
      final now = DateTime.utc(2026, 8, 22, 2);

      expect(
        WeatherAlertDeduplicator.shouldNotify(
          eventKey: 'event-a',
          nowUtc: now,
          lastEventKey: 'event-a',
          lastNotifiedAt: now.subtract(const Duration(hours: 8)),
          cooldown: const Duration(hours: 4),
        ),
        isFalse,
      );
      expect(
        WeatherAlertDeduplicator.shouldNotify(
          eventKey: 'event-b',
          nowUtc: now,
          lastEventKey: 'event-a',
          lastNotifiedAt: now.subtract(const Duration(hours: 2)),
          cooldown: const Duration(hours: 4),
        ),
        isFalse,
      );
      expect(
        WeatherAlertDeduplicator.shouldNotify(
          eventKey: 'event-b',
          nowUtc: now,
          lastEventKey: 'event-a',
          lastNotifiedAt: now.subtract(const Duration(hours: 5)),
          cooldown: const Duration(hours: 4),
        ),
        isTrue,
      );
    },
  );
}
