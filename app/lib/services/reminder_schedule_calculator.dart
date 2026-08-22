/// Pure, deterministic calculation of reminder notification occurrences.
library;

import 'package:timezone/timezone.dart' as tz;

import '../data/models/reminder_config.dart';

/// One notification and its corresponding pre-created log.
class ReminderOccurrence {
  const ReminderOccurrence({
    required this.notificationId,
    required this.title,
    required this.body,
    required this.payload,
    required this.scheduledTime,
  });

  final int notificationId;
  final String title;
  final String body;
  final String payload;
  final tz.TZDateTime scheduledTime;
}

/// Builds reminder occurrences without reading or changing application state.
abstract final class ReminderScheduleCalculator {
  static const _maxNotificationId = 0x7fffffff;

  /// Builds future occurrences for one enabled reminder configuration.
  ///
  /// The supplied [now] is the only clock input. Every occurrence is built
  /// from a calendar date in [now]'s location so a DST transition cannot
  /// shift the configured wall-clock time.
  static List<ReminderOccurrence> build({
    required ReminderConfig config,
    required String partnerName,
    required tz.TZDateTime now,
    String? partnerTimeZoneId,
    int occurrenceCount = 7,
  }) {
    if (occurrenceCount <= 0) return const [];

    final targetLocation = _targetLocation(
      config: config,
      deviceLocation: now.location,
      partnerTimeZoneId: partnerTimeZoneId,
    );
    if (targetLocation == null) return const [];

    return switch (config.category) {
      'sleep' => _buildSleep(
        config: config,
        partnerName: partnerName,
        now: now,
        targetLocation: targetLocation,
        occurrenceCount: occurrenceCount,
      ),
      'meal' => _buildMeals(
        config: config,
        partnerName: partnerName,
        now: now,
        targetLocation: targetLocation,
        occurrenceCount: occurrenceCount,
      ),
      'weather' => _buildWeather(
        config: config,
        partnerName: partnerName,
        now: now,
        targetLocation: targetLocation,
        occurrenceCount: occurrenceCount,
      ),
      'custom' => const [],
      _ => const [],
    };
  }

  static List<ReminderOccurrence> _buildSleep({
    required ReminderConfig config,
    required String partnerName,
    required tz.TZDateTime now,
    required tz.Location targetLocation,
    required int occurrenceCount,
  }) {
    final targetTime = _parseTime(config.config['target_sleep_time']);
    final advanceMinutes = _parseAdvance(config.config['advance_minutes']);
    if (targetTime == null || advanceMinutes == null) return const [];

    return _buildDaily(
      configKey: config.id,
      title: '🌙 睡觉提醒',
      body: '快到$partnerName的睡觉时间了，提醒Ta早点休息吧',
      config: config,
      now: now,
      targetLocation: targetLocation,
      targetTime: targetTime,
      advanceMinutes: advanceMinutes,
      occurrenceCount: occurrenceCount,
    );
  }

  static List<ReminderOccurrence> _buildMeals({
    required ReminderConfig config,
    required String partnerName,
    required tz.TZDateTime now,
    required tz.Location targetLocation,
    required int occurrenceCount,
  }) {
    final meals = config.config['meals'];
    if (meals is! List || meals.isEmpty) return const [];

    final occurrences = <ReminderOccurrence>[];
    final usedIds = <int>{};
    for (final rawMeal in meals) {
      if (rawMeal is! Map) continue;

      final name = rawMeal['name'];
      final targetTime = _parseTime(rawMeal['target_time']);
      final advanceMinutes = _parseAdvance(rawMeal['advance_minutes']);
      if (name is! String ||
          name.isEmpty ||
          targetTime == null ||
          advanceMinutes == null) {
        continue;
      }

      occurrences.addAll(
        _buildDaily(
          configKey: '${config.id}_$name',
          title: '🍚 $name提醒',
          body: '到$name时间了，提醒$partnerName按时吃饭吧',
          config: config,
          now: now,
          targetLocation: targetLocation,
          targetTime: targetTime,
          advanceMinutes: advanceMinutes,
          occurrenceCount: occurrenceCount,
          usedIds: usedIds,
        ),
      );
    }
    return occurrences;
  }

  static List<ReminderOccurrence> _buildWeather({
    required ReminderConfig config,
    required String partnerName,
    required tz.TZDateTime now,
    required tz.Location targetLocation,
    required int occurrenceCount,
  }) {
    final mode = config.config['mode'] as String? ?? 'daily_digest';
    if (mode == 'weather_change') return const [];
    if (mode != 'daily_digest') return const [];

    final configuredTime = config.config['digest_time'];
    final targetTime = configuredTime == null
        ? const _ParsedTime(8, 0)
        : _parseTime(configuredTime);
    if (targetTime == null) return const [];

    return _buildDaily(
      configKey: '${config.id}_weather',
      title: '🌦️ 天气关注',
      body: '新的一天开始了，看看$partnerName那边的天气吧',
      config: config,
      now: now,
      targetLocation: targetLocation,
      targetTime: targetTime,
      advanceMinutes: 0,
      occurrenceCount: occurrenceCount,
    );
  }

  static List<ReminderOccurrence> _buildDaily({
    required String configKey,
    required String title,
    required String body,
    required ReminderConfig config,
    required tz.TZDateTime now,
    required tz.Location targetLocation,
    required _ParsedTime targetTime,
    required int advanceMinutes,
    required int occurrenceCount,
    Set<int>? usedIds,
  }) {
    final ids = usedIds ?? <int>{};
    final deviceLocation = now.location;
    final targetNow = tz.TZDateTime.from(now, targetLocation);

    // Find the first target calendar date whose adjusted instant is not past.
    var firstTargetOffset = 0;
    while (true) {
      final scheduled = _scheduledForCalendarOffset(
        targetLocation: targetLocation,
        targetNow: targetNow,
        deviceLocation: deviceLocation,
        calendarOffset: firstTargetOffset,
        targetTime: targetTime,
        advanceMinutes: advanceMinutes,
      );
      if (!scheduled.isBefore(now)) break;
      firstTargetOffset++;
    }

    final occurrences = <ReminderOccurrence>[];
    for (var index = 0; index < occurrenceCount; index++) {
      final scheduled = _scheduledForCalendarOffset(
        targetLocation: targetLocation,
        targetNow: targetNow,
        deviceLocation: deviceLocation,
        calendarOffset: firstTargetOffset + index,
        targetTime: targetTime,
        advanceMinutes: advanceMinutes,
      );
      final notificationId = _uniqueNotificationId(configKey, index, ids);
      occurrences.add(
        ReminderOccurrence(
          notificationId: notificationId,
          title: title,
          body: body,
          payload: 'configId:${config.id}',
          scheduledTime: scheduled,
        ),
      );
    }
    return occurrences;
  }

  static tz.TZDateTime _scheduledForCalendarOffset({
    required tz.Location targetLocation,
    required tz.TZDateTime targetNow,
    required tz.Location deviceLocation,
    required int calendarOffset,
    required _ParsedTime targetTime,
    required int advanceMinutes,
  }) {
    final target = tz.TZDateTime(
      targetLocation,
      targetNow.year,
      targetNow.month,
      targetNow.day + calendarOffset,
      targetTime.hour,
      targetTime.minute,
    );
    final targetInstant = target.subtract(Duration(minutes: advanceMinutes));
    return tz.TZDateTime.from(targetInstant, deviceLocation);
  }

  static tz.Location? _targetLocation({
    required ReminderConfig config,
    required tz.Location deviceLocation,
    required String? partnerTimeZoneId,
  }) {
    final configuredId = config.timezoneId?.trim();
    if (configuredId != null && configuredId.isNotEmpty) {
      return _locationOrNull(configuredId);
    }

    if (config.timezoneMode == 'user') return deviceLocation;
    if (config.timezoneMode != 'partner') return null;

    final partnerId = partnerTimeZoneId?.trim();
    if (partnerId == null || partnerId.isEmpty) return null;
    return _locationOrNull(partnerId);
  }

  static tz.Location? _locationOrNull(String identifier) {
    try {
      return tz.getLocation(identifier);
    } catch (_) {
      return null;
    }
  }

  static _ParsedTime? _parseTime(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null || match.group(0) != value) return null;

    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return _ParsedTime(hour, minute);
  }

  static int? _parseAdvance(Object? value) {
    if (value is! int || value < 0 || value > 1440) return null;
    return value;
  }

  static int _uniqueNotificationId(
    String configKey,
    int dayOffset,
    Set<int> usedIds,
  ) {
    var id = _baseNotificationId(configKey, dayOffset);
    while (usedIds.contains(id)) {
      id = id == _maxNotificationId ? 1 : id + 1;
    }
    usedIds.add(id);
    return id;
  }

  /// Keep the existing config-key/hash plus day-offset ID strategy, while
  /// ensuring the result is always a positive signed 32-bit value.
  static int _baseNotificationId(String configKey, int dayOffset) {
    final raw = configKey.hashCode ^ (dayOffset * 1000);
    final id = raw.abs() % _maxNotificationId;
    return id == 0 ? 1 : id;
  }
}

class _ParsedTime {
  const _ParsedTime(this.hour, this.minute);

  final int hour;
  final int minute;
}
