/// TaWorld 本地数据模型 — 提醒日志
library;

class ReminderLog {
  final String id;
  final String configId;
  final String partnerId;
  final String? message;
  final String status; // triggered / sent / confirmed
  final DateTime triggeredAt;
  final DateTime? sentAt;
  final DateTime? confirmedAt;

  const ReminderLog({
    required this.id,
    required this.configId,
    required this.partnerId,
    this.message,
    required this.status,
    required this.triggeredAt,
    this.sentAt,
    this.confirmedAt,
  });

  factory ReminderLog.fromMap(Map<String, dynamic> map) {
    return ReminderLog(
      id: map['id'] as String,
      configId: map['config_id'] as String,
      partnerId: map['partner_id'] as String,
      message: map['message'] as String?,
      status: map['status'] as String? ?? 'triggered',
      triggeredAt: DateTime.parse(map['triggered_at'] as String),
      sentAt: map['sent_at'] != null
          ? DateTime.parse(map['sent_at'] as String)
          : null,
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.parse(map['confirmed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'config_id': configId,
      'partner_id': partnerId,
      'message': message,
      'status': status,
      'triggered_at': triggeredAt.toIso8601String(),
      'sent_at': sentAt?.toIso8601String(),
      'confirmed_at': confirmedAt?.toIso8601String(),
    };
  }

  ReminderLog copyWith({
    String? status,
    DateTime? sentAt,
    DateTime? confirmedAt,
  }) {
    return ReminderLog(
      id: id,
      configId: configId,
      partnerId: partnerId,
      message: message,
      status: status ?? this.status,
      triggeredAt: triggeredAt,
      sentAt: sentAt ?? this.sentAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
    );
  }

  String get statusLabel => switch (status) {
    'triggered' => '已触发',
    'sent' => '已发送',
    'confirmed' => '已确认',
    _ => status,
  };
}
