import 'dart:convert';

enum ToolExecutionStatus { success, partialSuccess, failure, information }

extension ToolExecutionStatusWireName on ToolExecutionStatus {
  String get wireName => switch (this) {
    ToolExecutionStatus.success => 'success',
    ToolExecutionStatus.partialSuccess => 'partial_success',
    ToolExecutionStatus.failure => 'failure',
    ToolExecutionStatus.information => 'information',
  };
}

class ToolMilestone {
  const ToolMilestone({
    required this.status,
    required this.title,
    required this.detail,
  });

  final ToolExecutionStatus status;
  final String title;
  final String detail;

  Map<String, Object?> toMap() => {
    'status': status.wireName,
    'title': title,
    'detail': detail,
  };

  factory ToolMilestone.fromMap(Map<String, dynamic> map) {
    final status = switch (map['status']) {
      'partial_success' => ToolExecutionStatus.partialSuccess,
      'failure' => ToolExecutionStatus.failure,
      'information' => ToolExecutionStatus.information,
      _ => ToolExecutionStatus.success,
    };
    return ToolMilestone(
      status: status,
      title: map['title'] as String? ?? '',
      detail: map['detail'] as String? ?? '',
    );
  }
}

class ToolExecutionResult {
  const ToolExecutionResult._({
    required this.toolName,
    required this.status,
    required this.modelMessage,
    required this.verified,
    this.entityId,
    this.milestone,
  });

  factory ToolExecutionResult.success({
    required String toolName,
    required String modelMessage,
    required String title,
    required String detail,
    String? entityId,
    bool verified = false,
  }) {
    return ToolExecutionResult._(
      toolName: toolName,
      status: ToolExecutionStatus.success,
      modelMessage: modelMessage,
      verified: verified,
      entityId: entityId,
      milestone: ToolMilestone(
        status: ToolExecutionStatus.success,
        title: title,
        detail: detail,
      ),
    );
  }

  factory ToolExecutionResult.partialSuccess({
    required String toolName,
    required String modelMessage,
    required String title,
    required String detail,
    String? entityId,
    bool verified = false,
  }) {
    return ToolExecutionResult._(
      toolName: toolName,
      status: ToolExecutionStatus.partialSuccess,
      modelMessage: modelMessage,
      verified: verified,
      entityId: entityId,
      milestone: ToolMilestone(
        status: ToolExecutionStatus.partialSuccess,
        title: title,
        detail: detail,
      ),
    );
  }

  factory ToolExecutionResult.failure({
    required String toolName,
    required String modelMessage,
    required String title,
    required String detail,
    String? entityId,
    bool verified = false,
  }) {
    return ToolExecutionResult._(
      toolName: toolName,
      status: ToolExecutionStatus.failure,
      modelMessage: modelMessage,
      verified: verified,
      entityId: entityId,
      milestone: ToolMilestone(
        status: ToolExecutionStatus.failure,
        title: title,
        detail: detail,
      ),
    );
  }

  factory ToolExecutionResult.information({
    required String toolName,
    required String modelMessage,
  }) {
    return ToolExecutionResult._(
      toolName: toolName,
      status: ToolExecutionStatus.information,
      modelMessage: modelMessage,
      verified: true,
    );
  }

  final String toolName;
  final ToolExecutionStatus status;
  final String modelMessage;
  final bool verified;
  final String? entityId;
  final ToolMilestone? milestone;

  String toModelContent() {
    return jsonEncode({
      'tool': toolName,
      'status': status.wireName,
      'verified': verified,
      'message': modelMessage,
      if (entityId != null) 'entity_id': entityId,
    });
  }
}
