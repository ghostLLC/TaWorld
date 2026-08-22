/// TaWorld 本地数据模型 — 关心的人
library;

class Partner {
  final String id;
  final String nickname;
  final String? avatarPath;
  final String type; // couple / family / friend
  final String? note;
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? district;

  /// IANA timezone identifier such as `Asia/Singapore`.
  final String? timezoneId;

  /// How [timezoneId] was obtained: `city_lookup` or `user_confirmed`.
  final String? timezoneSource;

  /// Whether the user explicitly confirmed the inferred timezone.
  final bool timezoneConfirmed;
  final String status; // active / dissolved
  final DateTime createdAt;
  final DateTime updatedAt;

  const Partner({
    required this.id,
    required this.nickname,
    this.avatarPath,
    required this.type,
    this.note,
    this.latitude,
    this.longitude,
    this.city,
    this.district,
    this.timezoneId,
    this.timezoneSource,
    this.timezoneConfirmed = false,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Partner.fromMap(Map<String, dynamic> map) {
    return Partner(
      id: map['id'] as String,
      nickname: map['nickname'] as String? ?? '',
      avatarPath: map['avatar_path'] as String?,
      type: map['type'] as String? ?? 'friend',
      note: map['note'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      city: map['city'] as String?,
      district: map['district'] as String?,
      timezoneId: map['timezone_id'] as String?,
      timezoneSource: map['timezone_source'] as String?,
      timezoneConfirmed: (map['timezone_confirmed'] as int? ?? 0) == 1,
      status: map['status'] as String? ?? 'active',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nickname': nickname,
      'avatar_path': avatarPath,
      'type': type,
      'note': note,
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'district': district,
      'timezone_id': timezoneId,
      'timezone_source': timezoneSource,
      'timezone_confirmed': timezoneConfirmed ? 1 : 0,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Partner copyWith({
    String? nickname,
    String? avatarPath,
    String? type,
    String? note,
    double? latitude,
    double? longitude,
    String? city,
    String? district,
    String? timezoneId,
    String? timezoneSource,
    bool? timezoneConfirmed,
    String? status,
    DateTime? updatedAt,
  }) {
    return Partner(
      id: id,
      nickname: nickname ?? this.nickname,
      avatarPath: avatarPath ?? this.avatarPath,
      type: type ?? this.type,
      note: note ?? this.note,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      city: city ?? this.city,
      district: district ?? this.district,
      timezoneId: timezoneId ?? this.timezoneId,
      timezoneSource: timezoneSource ?? this.timezoneSource,
      timezoneConfirmed: timezoneConfirmed ?? this.timezoneConfirmed,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  String get typeLabel => switch (type) {
    'couple' => '情侣',
    'partner' => '伴侣',
    'family' => '家人',
    'friend' => '朋友',
    _ => type,
  };
}
