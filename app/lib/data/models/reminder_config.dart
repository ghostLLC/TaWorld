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
  final String? parsingError;
  final Object? originalConfig;
  bool get isValid => parsingError == null;

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
    this.parsingError,
    this.originalConfig,
    this.timezoneMode = 'user',
    this.timezoneId,
    required this.createdAt,
    required this.updatedAt,
  }) : subjectId = subjectId ?? partnerId;

  factory ReminderConfig.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> decoded = {};
    String? error;
    try {
      final raw = map['config'];
      final value = raw is String ? jsonDecode(raw) : raw;
      if (value != null && value is! Map) {
        throw const FormatException('提醒配置格式无效');
      }
      decoded = Map<String, dynamic>.from(value as Map? ?? {});
    } on FormatException {
      error = '提醒配置无法读取，请编辑后重新保存';
    } on TypeError {
      error = '提醒配置格式不兼容，请编辑后重新保存';
    }
    String? stringField(String key, [String? fallback]) {
      final value = map[key];
      if (value == null) return fallback;
      if (value is String) return value;
      error ??= '提醒字段格式异常，请编辑后重新保存';
      return fallback;
    }

    DateTime dateField(String key) {
      final date = DateTime.tryParse(stringField(key) ?? '');
      if (date != null) return date;
      error ??= '提醒日期无法读取，请重新设置时间';
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final created = dateField('created_at'), updated = dateField('updated_at');
    final category = stringField('category', 'custom')!;
    final mode = stringField('timezone_mode', 'user')!;
    if (map['enabled'] is! int ||
        !const ['user', 'partner'].contains(mode) ||
        !const ['sleep', 'meal', 'weather', 'custom'].contains(category)) {
      error ??= '提醒设置不兼容，请编辑后重新保存';
    }
    return ReminderConfig(
      id: stringField('id', '')!,
      partnerId: stringField('partner_id', '')!,
      subjectKind: stringField('subject_kind', 'partner')!,
      subjectId: stringField('subject_id', stringField('partner_id', ''))!,
      category: category,
      enabled: map['enabled'] == 1,
      config: decoded,
      parsingError: error,
      originalConfig: error == null ? null : map['config'],
      timezoneMode: mode,
      timezoneId: stringField('timezone_id'),
      createdAt: created,
      updatedAt: updated,
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
      'config': parsingError == null ? jsonEncode(config) : originalConfig,
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
      parsingError: config == null ? parsingError : null,
      originalConfig: config == null ? originalConfig : null,
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
