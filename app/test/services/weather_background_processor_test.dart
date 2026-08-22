import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/data/models/reminder_config.dart';
import 'package:taworld/services/weather_background_processor.dart';
import 'package:taworld/services/weather_service.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  final timestamp = DateTime.utc(2026, 1, 1);
  final partner = Partner(
    id: 'partner-1',
    nickname: '小乐',
    type: 'friend',
    timezoneId: 'Asia/Singapore',
    timezoneConfirmed: true,
    status: 'active',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  ReminderConfig config(String id, String mode) => ReminderConfig(
    id: id,
    partnerId: partner.id,
    category: 'weather',
    enabled: true,
    config: {
      'mode': mode,
      'monitor_start': '07:00',
      'monitor_end': '23:00',
      'lead_minutes': 180,
      'cooldown_minutes': 240,
      'notify_conditions': ['rain'],
      'rain_probability_threshold': 60,
      'precipitation_mm_threshold': 1.0,
    },
    timezoneMode: 'partner',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  final weather = FullWeatherResult(
    current: const WeatherResult(text: '多云', temp: 30),
    sourceTimezoneId: 'Asia/Singapore',
    forecast: const [
      DailyForecast(
        date: '2026-08-22',
        maxTemp: 30,
        minTemp: 26,
        hourly: [
          HourlyForecast(
            date: '2026-08-22',
            hour: 11,
            text: '大雨',
            temp: 27,
            chanceOfRain: 90,
            precipMM: 4,
          ),
        ],
      ),
    ],
  );

  test(
    'processes only weather change configs and persists successful event',
    () async {
      final store = _MemoryStore();
      final sink = _CollectingSink();

      final count = await WeatherBackgroundProcessor.processPartner(
        partner: partner,
        configs: [
          config('digest', 'daily_digest'),
          config('change', 'weather_change'),
        ],
        weather: weather,
        nowUtc: DateTime.utc(2026, 8, 22, 2),
        deviceTimeZoneId: 'Asia/Shanghai',
        stateStore: store,
        alertSink: sink,
      );

      expect(count, 1);
      expect(sink.events.single.configId, 'change');
      expect(store.states.keys, ['change']);
    },
  );

  test('the same forecast event is delivered only once', () async {
    final store = _MemoryStore();
    final sink = _CollectingSink();
    final reminder = config('change', 'weather_change');

    await WeatherBackgroundProcessor.processPartner(
      partner: partner,
      configs: [reminder],
      weather: weather,
      nowUtc: DateTime.utc(2026, 8, 22, 2),
      deviceTimeZoneId: 'Asia/Shanghai',
      stateStore: store,
      alertSink: sink,
    );
    final secondCount = await WeatherBackgroundProcessor.processPartner(
      partner: partner,
      configs: [reminder],
      weather: weather,
      nowUtc: DateTime.utc(2026, 8, 22, 2, 30),
      deviceTimeZoneId: 'Asia/Shanghai',
      stateStore: store,
      alertSink: sink,
    );

    expect(secondCount, 0);
    expect(sink.events, hasLength(1));
  });

  test('a failed notification does not consume the event', () async {
    final store = _MemoryStore();
    final sink = _CollectingSink(shouldFail: true);

    await expectLater(
      WeatherBackgroundProcessor.processPartner(
        partner: partner,
        configs: [config('change', 'weather_change')],
        weather: weather,
        nowUtc: DateTime.utc(2026, 8, 22, 2),
        deviceTimeZoneId: 'Asia/Shanghai',
        stateStore: store,
        alertSink: sink,
      ),
      throwsStateError,
    );

    expect(store.states, isEmpty);
  });
}

class _MemoryStore implements WeatherAlertStateStore {
  final states = <String, WeatherAlertState>{};

  @override
  Future<WeatherAlertState?> read(String configId) async => states[configId];

  @override
  Future<void> write(String configId, WeatherAlertState state) async {
    states[configId] = state;
  }
}

class _CollectingSink implements WeatherAlertSink {
  _CollectingSink({this.shouldFail = false});

  final bool shouldFail;
  final events = <WeatherAlertDelivery>[];

  @override
  Future<void> show(WeatherAlertDelivery delivery) async {
    if (shouldFail) throw StateError('notification failed');
    events.add(delivery);
  }
}
