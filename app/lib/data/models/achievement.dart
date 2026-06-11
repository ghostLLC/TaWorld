/// TaWorld 本地数据模型 — 成就 & 用户成就进度
library;

import 'dart:convert';

class Achievement {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String category;
  final Map<String, dynamic> unlockCondition;
  final int points;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    required this.unlockCondition,
    required this.points,
  });

  factory Achievement.fromMap(Map<String, dynamic> map) {
    return Achievement(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      icon: map['icon'] as String? ?? 'trophy',
      category: map['category'] as String? ?? 'general',
      unlockCondition: map['unlock_condition'] is String
          ? jsonDecode(map['unlock_condition'] as String) as Map<String, dynamic>
          : (map['unlock_condition'] as Map<String, dynamic>?) ?? {},
      points: map['points'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'category': category,
      'unlock_condition': jsonEncode(unlockCondition),
      'points': points,
    };
  }

  String get unlockType => unlockCondition['type'] as String? ?? 'count';
  int get target => unlockCondition['target'] as int? ?? 1;
}

class UserAchievement {
  final String id;
  final String achievementId;
  final int progress;
  final bool unlocked;
  final DateTime? unlockedAt;

  // Joined fields from achievements table
  final String? achievementName;
  final String? achievementIcon;
  final String? achievementDescription;
  final int? achievementPoints;

  const UserAchievement({
    required this.id,
    required this.achievementId,
    required this.progress,
    required this.unlocked,
    this.unlockedAt,
    this.achievementName,
    this.achievementIcon,
    this.achievementDescription,
    this.achievementPoints,
  });

  factory UserAchievement.fromMap(Map<String, dynamic> map) {
    return UserAchievement(
      id: map['id'] as String,
      achievementId: map['achievement_id'] as String,
      progress: map['progress'] as int? ?? 0,
      unlocked: (map['unlocked'] as int? ?? 0) == 1,
      unlockedAt: map['unlocked_at'] != null
          ? DateTime.parse(map['unlocked_at'] as String)
          : null,
      achievementName: map['name'] as String?,
      achievementIcon: map['icon'] as String?,
      achievementDescription: map['description'] as String?,
      achievementPoints: map['points'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'achievement_id': achievementId,
      'progress': progress,
      'unlocked': unlocked ? 1 : 0,
      'unlocked_at': unlockedAt?.toIso8601String(),
    };
  }

  UserAchievement copyWith({
    int? progress,
    bool? unlocked,
    DateTime? unlockedAt,
  }) {
    return UserAchievement(
      id: id,
      achievementId: achievementId,
      progress: progress ?? this.progress,
      unlocked: unlocked ?? this.unlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      achievementName: achievementName,
      achievementIcon: achievementIcon,
      achievementDescription: achievementDescription,
      achievementPoints: achievementPoints,
    );
  }
}

/// 预设成就种子数据
const List<Map<String, dynamic>> kSeedAchievements = [
  {
    'name': '初次守护',
    'description': '首次成功完成天气提醒闭环',
    'icon': '🌂',
    'category': 'weather',
    'unlock_condition': '{"type":"reminder_complete","target":1}',
    'points': 10,
  },
  {
    'name': '连续守护7天',
    'description': '连续7天完成至少1次提醒',
    'icon': '🔥',
    'category': 'streak',
    'unlock_condition': '{"type":"streak_days","target":7}',
    'points': 50,
  },
  {
    'name': '晚安大使',
    'description': '累计完成30次睡觉提醒',
    'icon': '🌙',
    'category': 'sleep',
    'unlock_condition': '{"type":"sleep_reminder_count","target":30}',
    'points': 100,
  },
  {
    'name': '干饭督导',
    'description': '累计完成30次吃饭提醒',
    'icon': '🍚',
    'category': 'meal',
    'unlock_condition': '{"type":"meal_reminder_count","target":30}',
    'points': 100,
  },
  {
    'name': '百日陪伴',
    'description': '关系建立满100天且活跃',
    'icon': '💯',
    'category': 'milestone',
    'unlock_condition': '{"type":"relationship_days","target":100}',
    'points': 200,
  },
  {
    'name': '创意达人',
    'description': '创建5个自定义提醒',
    'icon': '🎨',
    'category': 'custom',
    'unlock_condition': '{"type":"custom_reminder_count","target":5}',
    'points': 50,
  },
  {
    'name': '双向奔赴',
    'description': '和Ta互相完成提醒各10次',
    'icon': '❤️',
    'category': 'mutual',
    'unlock_condition': '{"type":"mutual_reminder_count","target":10}',
    'points': 150,
  },
];
