import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/reminder_config/weather_reminder_form_value.dart';

void main() {
  test('legacy weather config becomes an 08:00 daily digest', () {
    final value = WeatherReminderFormValue.fromConfig(const {
      'notify_conditions': ['rain'],
    }, timezoneMode: 'user');

    expect(value.mode, WeatherReminderMode.dailyDigest);
    expect(value.digestTime, '08:00');
    expect(value.timezoneMode, 'user');
    expect(value.toConfig(), containsPair('mode', 'daily_digest'));
  });

  test('weather change form preserves monitoring and threshold settings', () {
    final value = WeatherReminderFormValue.fromConfig(const {
      'mode': 'weather_change',
      'monitor_start': '08:00',
      'monitor_end': '22:00',
      'lead_minutes': 120,
      'cooldown_minutes': 360,
      'notify_conditions': ['rain', 'temperature_drop'],
      'rain_probability_threshold': 70,
      'precipitation_mm_threshold': 2.0,
      'temperature_change_threshold': 8,
    }, timezoneMode: 'partner');

    expect(value.mode, WeatherReminderMode.weatherChange);
    expect(value.monitorStart, '08:00');
    expect(value.monitorEnd, '22:00');
    expect(value.leadMinutes, 120);
    expect(value.cooldownMinutes, 360);
    expect(value.conditions, ['rain', 'temperature_drop']);
    expect(value.timezoneMode, 'partner');
    expect(value.toConfig(), {
      'mode': 'weather_change',
      'monitor_start': '08:00',
      'monitor_end': '22:00',
      'lead_minutes': 120,
      'cooldown_minutes': 360,
      'notify_conditions': ['rain', 'temperature_drop'],
      'rain_probability_threshold': 70,
      'precipitation_mm_threshold': 2.0,
      'temperature_change_threshold': 8,
      'cold_temperature_threshold': 0,
      'heat_temperature_threshold': 35,
    });
  });
}
