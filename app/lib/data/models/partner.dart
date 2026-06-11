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
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  String get typeLabel => switch (type) {
    'couple' => '情侣',
    'family' => '家人',
    'friend' => '朋友',
    _ => '朋友',
  };
}
