/// TaWorld AI Wiki 事实模型
library;

class AiWikiFact {
  final String id;
  final String category; // user_pref / partner_fact / event / relationship / user_identity
  final String? entityId; // 关联的 partner_id 或 null
  final String content;
  final String source; // chat / proactive / manual / system
  final double importance; // 0.0~1.0
  final double strength; // 随时间衰减 0.0~1.0
  final int accessCount;
  final DateTime? lastAccessed;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiWikiFact({
    required this.id,
    required this.category,
    this.entityId,
    required this.content,
    this.source = 'chat',
    this.importance = 0.5,
    this.strength = 1.0,
    this.accessCount = 0,
    this.lastAccessed,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiWikiFact.fromMap(Map<String, dynamic> map) {
    return AiWikiFact(
      id: map['id'] as String,
      category: map['category'] as String? ?? 'user_pref',
      entityId: map['entity_id'] as String?,
      content: map['content'] as String? ?? '',
      source: map['source'] as String? ?? 'chat',
      importance: (map['importance'] as num?)?.toDouble() ?? 0.5,
      strength: (map['strength'] as num?)?.toDouble() ?? 1.0,
      accessCount: map['access_count'] as int? ?? 0,
      lastAccessed: map['last_accessed'] != null
          ? DateTime.parse(map['last_accessed'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'entity_id': entityId,
      'content': content,
      'source': source,
      'importance': importance,
      'strength': strength,
      'access_count': accessCount,
      'last_accessed': lastAccessed?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  AiWikiFact copyWith({
    String? content,
    double? importance,
    double? strength,
    int? accessCount,
    DateTime? lastAccessed,
    DateTime? updatedAt,
  }) {
    return AiWikiFact(
      id: id,
      category: category,
      entityId: entityId,
      content: content ?? this.content,
      source: source,
      importance: importance ?? this.importance,
      strength: strength ?? this.strength,
      accessCount: accessCount ?? this.accessCount,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// 综合得分 = importance * strength，用于排序
  double get score => importance * strength;
}
