/// TaWorld 本地数据模型 — 用户
library;

class LocalUser {
  final String id;
  final String nickname;
  final String? avatarPath;
  final String? phone;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalUser({
    required this.id,
    required this.nickname,
    this.avatarPath,
    this.phone,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalUser.fromMap(Map<String, dynamic> map) {
    return LocalUser(
      id: map['id'] as String,
      nickname: map['nickname'] as String? ?? '',
      avatarPath: map['avatar_path'] as String?,
      phone: map['phone'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nickname': nickname,
      'avatar_path': avatarPath,
      'phone': phone,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  LocalUser copyWith({
    String? nickname,
    String? avatarPath,
    String? phone,
    DateTime? updatedAt,
  }) {
    return LocalUser(
      id: id,
      nickname: nickname ?? this.nickname,
      avatarPath: avatarPath ?? this.avatarPath,
      phone: phone ?? this.phone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
