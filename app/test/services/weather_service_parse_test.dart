import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/services/weather_service.dart';

void main() {
  test('Open-Meteo parser preserves the forecast source IANA timezone', () {
    final result = WeatherService.parseOpenMeteoResponse({
      'timezone': 'America/Los_Angeles',
      'current': {
        'weather_code': 0,
        'temperature_2m': 20,
        'relative_humidity_2m': 50,
        'wind_direction_10m': 0,
      },
      'daily': {
        'time': ['2026-08-22'],
        'temperature_2m_max': [25],
        'temperature_2m_min': [15],
      },
      'hourly': {
        'time': ['2026-08-22T11:00'],
        'temperature_2m': [21],
        'weather_code': [61],
        'precipitation_probability': [80],
        'precipitation': [2.5],
      },
    });

    expect(result.sourceTimezoneId, 'America/Los_Angeles');
    expect(result.forecast.single.hourly.single.date, '2026-08-22');
    expect(result.forecast.single.hourly.single.hour, 11);
  });
}
