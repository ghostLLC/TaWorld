/// Deterministic translation from AI function-call arguments to reminder data.
///
/// Keeping this logic outside the chat widget makes timezone and weather-mode
/// semantics testable before any database or notification side effect occurs.
library;

import '../data/models/reminder_config.dart';
import '../data/models/partner.dart';
import 'package:timezone/timezone.dart' as tz;

class ReminderToolPlan {
  const ReminderToolPlan({
    required this.partnerName,
    required this.category,
    required this.timezoneMode,
    required this.config,
    this.timezoneId,
    this.displayTime,
    this.subjectKind = 'partner',
  });

  final String partnerName;
  final String category;
  final String timezoneMode;
  final String? timezoneId;
  final String? displayTime;
  final Map<String, dynamic> config;
  final String subjectKind;

  bool get isSelfReminder => subjectKind == 'user';

  bool get monitorsWeatherChanges =>
      category == 'weather' && config['mode'] == 'weather_change';
}

class ReminderToolParseResult {
  const ReminderToolParseResult._({this.plan, this.error});

  factory ReminderToolParseResult.success(ReminderToolPlan plan) =>
      ReminderToolParseResult._(plan: plan);

  factory ReminderToolParseResult.failure(String error) =>
      ReminderToolParseResult._(error: error);

  final ReminderToolPlan? plan;
  final String? error;
}

class ReminderDeletionSelection {
  const ReminderDeletionSelection({required this.targets, this.error});

  final List<ReminderConfig> targets;
  final String? error;
}

abstract final class ReminderToolPlanner {
  static const _categories = {'sleep', 'meal', 'weather'};
  static const _timeBases = {'user', 'partner'};
  static const _weatherModes = {'daily_digest', 'weather_change'};

  static ReminderToolParseResult parse(Map<String, dynamic> arguments) {
    final requestedSubject = (arguments['subject'] as String? ?? '').trim();
    final requestedName = (arguments['partner_name'] as String? ?? '').trim();
    final isSelf =
        requestedSubject == 'self' ||
        const {'我', '自己', '本人', '用户'}.contains(requestedName);
    final partnerName = isSelf ? '你' : requestedName;
    if (!isSelf && partnerName.isEmpty) {
      return ReminderToolParseResult.failure('缺少要关心的人');
    }

    final category = (arguments['category'] as String? ?? '').trim();
    if (!_categories.contains(category)) {
      return ReminderToolParseResult.failure('不支持的提醒类别：$category');
    }

    final weatherMode = category == 'weather'
        ? (arguments['weather_mode'] as String? ?? 'daily_digest').trim()
        : null;
    if (weatherMode != null && !_weatherModes.contains(weatherMode)) {
      return ReminderToolParseResult.failure('不支持的天气提醒模式：$weatherMode');
    }

    final defaultTimeBasis = isSelf
        ? 'user'
        : switch ((category, weatherMode)) {
            ('sleep', _) ||
            ('meal', _) ||
            ('weather', 'weather_change') => 'partner',
            _ => 'user',
          };
    final timezoneMode = isSelf
        ? 'user'
        : (arguments['time_basis'] as String? ?? defaultTimeBasis).trim();
    if (!_timeBases.contains(timezoneMode)) {
      return ReminderToolParseResult.failure('时间基准必须是 user 或 partner');
    }

    final timezoneId = _trimmedString(arguments['timezone_id']);
    final customMessage = _trimmedString(arguments['message']);

    if (category == 'weather' && weatherMode == 'weather_change') {
      final start = _clock(arguments['monitor_start'] ?? '07:00');
      final end = _clock(arguments['monitor_end'] ?? '23:00');
      if (start == null || end == null) {
        return ReminderToolParseResult.failure('天气监测时段格式错误，应为 HH:mm');
      }

      final conditions = _stringList(arguments['notify_conditions'], const [
        'rain',
        'snow',
        'temperature_drop',
        'temperature_rise',
      ]);
      final config = <String, dynamic>{
        ...ReminderConfig.defaultConfigFor('weather'),
        'mode': 'weather_change',
        'monitor_start': start,
        'monitor_end': end,
        'lead_minutes': _boundedInt(
          arguments['lead_minutes'],
          fallback: 180,
          min: 30,
          max: 720,
        ),
        'cooldown_minutes': _boundedInt(
          arguments['cooldown_minutes'],
          fallback: 240,
          min: 30,
          max: 1440,
        ),
        'notify_conditions': conditions,
        'rain_probability_threshold': _boundedNumber(
          arguments['rain_probability_threshold'],
          fallback: 60,
          min: 0,
          max: 100,
        ),
        'precipitation_mm_threshold': _boundedNumber(
          arguments['precipitation_mm_threshold'],
          fallback: 1,
          min: 0,
          max: 100,
        ),
        'temperature_change_threshold': _boundedNumber(
          arguments['temperature_change_threshold'],
          fallback: 6,
          min: 1,
          max: 30,
        ),
      };
      return ReminderToolParseResult.success(
        ReminderToolPlan(
          partnerName: partnerName,
          category: category,
          timezoneMode: timezoneMode,
          timezoneId: timezoneId,
          config: config,
          subjectKind: isSelf ? 'user' : 'partner',
        ),
      );
    }

    final time = _clock(arguments['time']);
    if (time == null) {
      return ReminderToolParseResult.failure('提醒时间格式错误，应为 HH:mm');
    }

    final config = switch (category) {
      'sleep' => <String, dynamic>{
        'target_sleep_time': time,
        'advance_minutes': _boundedInt(
          arguments['advance_minutes'],
          fallback: 30,
          min: 0,
          max: 720,
        ),
      },
      'meal' => <String, dynamic>{
        'meals': [
          {
            'name': customMessage ?? '吃饭',
            'target_time': time,
            'advance_minutes': _boundedInt(
              arguments['advance_minutes'],
              fallback: 15,
              min: 0,
              max: 720,
            ),
          },
        ],
      },
      'weather' => <String, dynamic>{
        ...ReminderConfig.defaultConfigFor('weather'),
        'mode': 'daily_digest',
        'digest_time': time,
      },
      _ => const <String, dynamic>{},
    };

    return ReminderToolParseResult.success(
      ReminderToolPlan(
        partnerName: partnerName,
        category: category,
        timezoneMode: timezoneMode,
        timezoneId: timezoneId,
        displayTime: time,
        config: config,
        subjectKind: isSelf ? 'user' : 'partner',
      ),
    );
  }

  /// Resolves partner-local wall-clock semantics without trusting a guessed
  /// or stale profile timezone. An explicit tool argument is treated as the
  /// user's current confirmation; otherwise the profile must be confirmed.
  static String? resolveTimezoneId({
    required ReminderToolPlan plan,
    required Partner partner,
  }) {
    if (plan.timezoneMode == 'user') return null;
    if (plan.timezoneMode != 'partner') return null;

    final explicit = plan.timezoneId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _validTimezoneOrNull(explicit);
    }

    if (!partner.timezoneConfirmed) return null;
    final profile = partner.timezoneId?.trim();
    if (profile == null || profile.isEmpty) return null;
    return _validTimezoneOrNull(profile);
  }

  /// Selects one reminder kind for deletion. Daily weather and weather-change
  /// monitoring are independent kinds, so an unspecified mode is rejected
  /// when both exist instead of deleting both silently.
  static ReminderDeletionSelection selectDeletionTargets(
    List<ReminderConfig> configs, {
    required String category,
    String? weatherMode,
  }) {
    final candidates = configs
        .where((config) => config.category == category)
        .toList();
    if (category != 'weather') {
      return ReminderDeletionSelection(targets: candidates);
    }

    final normalizedMode = weatherMode?.trim();
    if (normalizedMode != null &&
        normalizedMode.isNotEmpty &&
        !_weatherModes.contains(normalizedMode)) {
      return ReminderDeletionSelection(
        targets: const [],
        error: '不支持的天气提醒模式：$normalizedMode',
      );
    }

    if (normalizedMode == null || normalizedMode.isEmpty) {
      final modes = candidates
          .map((config) => config.config['mode'] as String? ?? 'daily_digest')
          .toSet();
      if (modes.length > 1) {
        return const ReminderDeletionSelection(
          targets: [],
          error: '同时存在每日天气简报和天气突变监测，请先确认要删除哪一种模式',
        );
      }
      return ReminderDeletionSelection(targets: candidates);
    }

    return ReminderDeletionSelection(
      targets: candidates
          .where(
            (config) =>
                (config.config['mode'] as String? ?? 'daily_digest') ==
                normalizedMode,
          )
          .toList(),
    );
  }

  static String? _validTimezoneOrNull(String identifier) {
    try {
      tz.getLocation(identifier);
      return identifier;
    } catch (_) {
      return null;
    }
  }

  static String? _clock(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String? _trimmedString(Object? value) {
    if (value is! String) return null;
    final result = value.trim();
    return result.isEmpty ? null : result;
  }

  static List<String> _stringList(Object? value, List<String> fallback) {
    if (value is! List) return List<String>.from(fallback);
    final result = value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    return result.isEmpty ? List<String>.from(fallback) : result;
  }

  static int _boundedInt(
    Object? value, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? fallback).clamp(min, max);
  }

  static num _boundedNumber(
    Object? value, {
    required num fallback,
    required num min,
    required num max,
  }) {
    final parsed = value is num ? value : num.tryParse('$value');
    return (parsed ?? fallback).clamp(min, max);
  }
}
