class ReminderOccurrenceRecord {
  const ReminderOccurrenceRecord({
    required this.id,
    required this.configId,
    required this.subjectKind,
    required this.subjectId,
    required this.status,
    required this.scheduledFor,
    required this.createdAt,
    required this.updatedAt,
    this.message,
    this.deliveredAt,
    this.respondedAt,
    this.snoozedUntil,
    this.response,
  });

  final String id;
  final String configId;
  final String subjectKind;
  final String subjectId;
  final String status;
  final DateTime scheduledFor;
  final String? message;
  final DateTime? deliveredAt;
  final DateTime? respondedAt;
  final DateTime? snoozedUntil;
  final String? response;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ReminderOccurrenceRecord.fromMap(Map<String, Object?> map) {
    DateTime? optionalTime(String key) {
      final raw = map[key] as String?;
      return raw == null ? null : DateTime.parse(raw);
    }

    return ReminderOccurrenceRecord(
      id: map['id'] as String,
      configId: map['config_id'] as String,
      subjectKind: map['subject_kind'] as String,
      subjectId: map['subject_id'] as String,
      status: map['status'] as String,
      scheduledFor: DateTime.parse(map['scheduled_for'] as String),
      message: map['message'] as String?,
      deliveredAt: optionalTime('delivered_at'),
      respondedAt: optionalTime('responded_at'),
      snoozedUntil: optionalTime('snoozed_until'),
      response: map['response'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
