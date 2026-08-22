/// TaWorld 本地数据模型 — 提醒配置
library;

import 'dart:convert';

class ReminderConfig {
  final String id;
  final String partnerId;
  final String subjectKind; // partner / user
  final String subjectId;
  final String category; // weather / sleep / meal / custom
  final bool enabled;
  final Map<String, dynamic> config;

  /// Which person's wall-clock the configured time follows.
  ///
  /// `user` follows the device location. `partner` follows [timezoneId], or
  /// the linked partner profile when no per-reminder override is stored.
  final String timezoneMode; // user / partner

  /// Optional IANA location override, for example `Asia/Singapore`.
  final String? timezoneId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReminderConfig({
    required this.id,
    required this.partnerId,
    this.subjectKind = 'partner',
    String? subjectId,
    required this.category,
    required this.enabled,
    required this.config,
    this.timezoneMode = 'user',
    this.timezoneId,
    required this.createdAt,
    required this.updatedAt,
  }) : subjectId = subjectId ?? partnerId;

  factory ReminderConfig.fromMap(Map<String, dynamic> map) {
    return ReminderConfig(
      id: map['id'] as String,
      partnerId: map['partner_id'] as String? ?? '',
      subjectKind: map['subject_kind'] as String? ?? 'partner',
      subjectId:
          map['subject_id'] as String? ?? map['partner_id'] as String? ?? '',
      category: map['category'] as String,
      enabled: (map['enabled'] as int) == 1,
      config: map['config'] is String
          ? jsonDecode(map['config'] as String) as Map<String, dynamic>
          : (map['config'] as Map<String, dynamic>?) ?? {},
      timezoneMode: map['timezone_mode'] as String? ?? 'user',
      timezoneId: map['timezone_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'partner_id': partnerId.isEmpty ? null : partnerId,
      'subject_kind': subjectKind,
      'subject_id': subjectId,
      'category': category,
      'enabled': enabled ? 1 : 0,
      'config': jsonEncode(config),
      'timezone_mode': timezoneMode,
      'timezone_id': timezoneId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ReminderConfig copyWith({
    bool? enabled,
    Map<String, dynamic>? config,
    String? timezoneMode,
    String? timezoneId,
    bool clearTimezoneId = false,
    DateTime? updatedAt,
  }) {
    return ReminderConfig(
      id: id,
      partnerId: partnerId,
      subjectKind: subjectKind,
      subjectId: subjectId,
      category: category,
      enabled: enabled ?? this.enabled,
      config: config ?? this.config,
      timezoneMode: timezoneMode ?? this.timezoneMode,
      timezoneId: clearTimezoneId ? null : timezoneId ?? this.timezoneId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  bool get isSelfReminder => subjectKind == 'user';

  String get categoryLabel => switch (category) {
    'weather' => '天气提醒',
    'sleep' => '睡觉提醒',
    'meal' => '吃饭提醒',
    'custom' => '自定义提醒',
    _ => '提醒',
  };

  String get categoryEmoji => switch (category) {
    'weather' => '🌦️',
    'sleep' => '🌙',
    'meal' => '🍚',
    'custom' => '💝',
    _ => '💝',
  };

  String get categoryIconAsset {
    switch (category) {
      case 'weather':
        return 'assets/images/icon_weather_category.png';
      case 'sleep':
        return 'assets/images/icon_sleep_category.png';
      case 'meal':
        return 'assets/images/icon_meal_category.png';
      case 'custom':
      default:
        return 'assets/images/icon_custom_category.png';
    }
  }

  /// 默认配置模板
  static Map<String, dynamic> defaultConfigFor(String category) {
    return switch (category) {
      'weather' => {
        'mode': 'daily_digest',
        'digest_time': '08:00',
        'notify_conditions': ['rain', 'snow', 'extreme_cold', 'extreme_heat'],
        'custom_messages': {},
      },
      'sleep' => {'target_sleep_time': '23:00', 'advance_minutes': 30},
      'meal' => {
        'meals': [
          {'name': '早餐', 'target_time': '08:00', 'advance_minutes': 15},
          {'name': '午餐', 'target_time': '12:00', 'advance_minutes': 15},
          {'name': '晚餐', 'target_time': '18:00', 'advance_minutes': 15},
        ],
      },
      _ => {},
    };
  }
}
