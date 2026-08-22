enum WeatherReminderMode { dailyDigest, weatherChange }

class WeatherReminderFormValue {
  const WeatherReminderFormValue({
    required this.mode,
    required this.timezoneMode,
    required this.digestTime,
    required this.monitorStart,
    required this.monitorEnd,
    required this.leadMinutes,
    required this.cooldownMinutes,
    required this.conditions,
    required this.rainProbabilityThreshold,
    required this.precipitationMmThreshold,
    required this.temperatureChangeThreshold,
    required this.coldTemperatureThreshold,
    required this.heatTemperatureThreshold,
  });

  factory WeatherReminderFormValue.fromConfig(
    Map<String, dynamic> config, {
    required String timezoneMode,
  }) {
    return WeatherReminderFormValue(
      mode: config['mode'] == 'weather_change'
          ? WeatherReminderMode.weatherChange
          : WeatherReminderMode.dailyDigest,
      timezoneMode: timezoneMode == 'partner' ? 'partner' : 'user',
      digestTime: config['digest_time'] as String? ?? '08:00',
      monitorStart: config['monitor_start'] as String? ?? '07:00',
      monitorEnd: config['monitor_end'] as String? ?? '23:00',
      leadMinutes: config['lead_minutes'] as int? ?? 180,
      cooldownMinutes: config['cooldown_minutes'] as int? ?? 240,
      conditions:
          (config['notify_conditions'] as List?)
              ?.whereType<String>()
              .toList() ??
          const ['rain', 'snow', 'temperature_drop', 'temperature_rise'],
      rainProbabilityThreshold:
          (config['rain_probability_threshold'] as num?)?.round() ?? 60,
      precipitationMmThreshold:
          (config['precipitation_mm_threshold'] as num?)?.toDouble() ?? 1,
      temperatureChangeThreshold:
          (config['temperature_change_threshold'] as num?)?.round() ?? 6,
      coldTemperatureThreshold:
          (config['cold_temperature_threshold'] as num?)?.round() ?? 0,
      heatTemperatureThreshold:
          (config['heat_temperature_threshold'] as num?)?.round() ?? 35,
    );
  }

  final WeatherReminderMode mode;
  final String timezoneMode;
  final String digestTime;
  final String monitorStart;
  final String monitorEnd;
  final int leadMinutes;
  final int cooldownMinutes;
  final List<String> conditions;
  final int rainProbabilityThreshold;
  final double precipitationMmThreshold;
  final int temperatureChangeThreshold;
  final int coldTemperatureThreshold;
  final int heatTemperatureThreshold;

  WeatherReminderFormValue copyWith({
    WeatherReminderMode? mode,
    String? timezoneMode,
    String? digestTime,
    String? monitorStart,
    String? monitorEnd,
    int? leadMinutes,
    int? cooldownMinutes,
    List<String>? conditions,
    int? rainProbabilityThreshold,
    double? precipitationMmThreshold,
    int? temperatureChangeThreshold,
    int? coldTemperatureThreshold,
    int? heatTemperatureThreshold,
  }) {
    return WeatherReminderFormValue(
      mode: mode ?? this.mode,
      timezoneMode: timezoneMode ?? this.timezoneMode,
      digestTime: digestTime ?? this.digestTime,
      monitorStart: monitorStart ?? this.monitorStart,
      monitorEnd: monitorEnd ?? this.monitorEnd,
      leadMinutes: leadMinutes ?? this.leadMinutes,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      conditions: conditions ?? this.conditions,
      rainProbabilityThreshold:
          rainProbabilityThreshold ?? this.rainProbabilityThreshold,
      precipitationMmThreshold:
          precipitationMmThreshold ?? this.precipitationMmThreshold,
      temperatureChangeThreshold:
          temperatureChangeThreshold ?? this.temperatureChangeThreshold,
      coldTemperatureThreshold:
          coldTemperatureThreshold ?? this.coldTemperatureThreshold,
      heatTemperatureThreshold:
          heatTemperatureThreshold ?? this.heatTemperatureThreshold,
    );
  }

  Map<String, dynamic> toConfig() {
    if (mode == WeatherReminderMode.dailyDigest) {
      return {'mode': 'daily_digest', 'digest_time': digestTime};
    }
    return {
      'mode': 'weather_change',
      'monitor_start': monitorStart,
      'monitor_end': monitorEnd,
      'lead_minutes': leadMinutes,
      'cooldown_minutes': cooldownMinutes,
      'notify_conditions': conditions,
      'rain_probability_threshold': rainProbabilityThreshold,
      'precipitation_mm_threshold': precipitationMmThreshold,
      'temperature_change_threshold': temperatureChangeThreshold,
      'cold_temperature_threshold': coldTemperatureThreshold,
      'heat_temperature_threshold': heatTemperatureThreshold,
    };
  }
}
