/// Testable orchestration for best-effort background weather alerts.
library;

import '../data/models/partner.dart';
import '../data/models/reminder_config.dart';
import 'weather_change_monitor.dart';
import 'weather_service.dart';

class WeatherAlertState {
  const WeatherAlertState({
    required this.eventKey,
    required this.notifiedAtUtc,
  });

  final String eventKey;
  final DateTime notifiedAtUtc;
}

abstract interface class WeatherAlertStateStore {
  Future<WeatherAlertState?> read(String configId);

  Future<void> write(String configId, WeatherAlertState state);
}

class WeatherAlertDelivery {
  const WeatherAlertDelivery({
    required this.configId,
    required this.partnerId,
    required this.event,
  });

  final String configId;
  final String partnerId;
  final WeatherAlertEvent event;
}

abstract interface class WeatherAlertSink {
  Future<void> show(WeatherAlertDelivery delivery);
}

abstract final class WeatherBackgroundProcessor {
  /// Returns the number of alerts that were actually delivered.
  static Future<int> processPartner({
    required Partner partner,
    required List<ReminderConfig> configs,
    required FullWeatherResult weather,
    required DateTime nowUtc,
    required String deviceTimeZoneId,
    required WeatherAlertStateStore stateStore,
    required WeatherAlertSink alertSink,
  }) async {
    var delivered = 0;
    for (final config in configs) {
      if (!config.enabled ||
          config.category != 'weather' ||
          config.config['mode'] != 'weather_change') {
        continue;
      }

      final event = WeatherChangeMonitor.evaluate(
        config: config,
        partner: partner,
        weather: weather,
        nowUtc: nowUtc,
        deviceTimeZoneId: deviceTimeZoneId,
      );
      if (event == null) continue;

      final previous = await stateStore.read(config.id);
      final shouldNotify = WeatherAlertDeduplicator.shouldNotify(
        eventKey: event.eventKey,
        nowUtc: nowUtc,
        lastEventKey: previous?.eventKey,
        lastNotifiedAt: previous?.notifiedAtUtc,
        cooldown: event.cooldown,
      );
      if (!shouldNotify) continue;

      await alertSink.show(
        WeatherAlertDelivery(
          configId: config.id,
          partnerId: partner.id,
          event: event,
        ),
      );
      await stateStore.write(
        config.id,
        WeatherAlertState(
          eventKey: event.eventKey,
          notifiedAtUtc: nowUtc.toUtc(),
        ),
      );
      delivered++;
    }
    return delivered;
  }
}
