/// TaWorld 本地数据模型 — 提醒配置
library;

import 'dart:convert';

class ReminderConfig {
  final String id;
  final String partnerId;
  final String category; // weather / sleep / meal / custom
  final bool enabled;
  final Map<String, dynamic> config;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReminderConfig({
    required this.id,
    required this.partnerId,
    required this.category,
    required this.enabled,
    required this.config,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReminderConfig.fromMap(Map<String, dynamic> map) {
    return ReminderConfig(
      id: map['id'] as String,
      partnerId: map['partner_id'] as String,
      category: map['category'] as String,
      enabled: (map['enabled'] as int) == 1,
      config: map['config'] is String
          ? jsonDecode(map['config'] as String) as Map<String, dynamic>
          : (map['config'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'partner_id': partnerId,
      'category': category,
      'enabled': enabled ? 1 : 0,
      'config': jsonEncode(config),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ReminderConfig copyWith({
    bool? enabled,
    Map<String, dynamic>? config,
    DateTime? updatedAt,
  }) {
    return ReminderConfig(
      id: id,
      partnerId: partnerId,
      category: category,
      enabled: enabled ?? this.enabled,
      config: config ?? this.config,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

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

  /// 默认配置模板
  static Map<String, dynamic> defaultConfigFor(String category) {
    return switch (category) {
      'weather' => {
        'notify_conditions': ['rain', 'snow', 'extreme_cold', 'extreme_heat'],
        'custom_messages': {},
      },
      'sleep' => {
        'target_sleep_time': '23:00',
        'advance_minutes': 30,
      },
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
