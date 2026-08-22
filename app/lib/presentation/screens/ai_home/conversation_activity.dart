/// Explicit phases for the assistant's visible conversation activity.
enum AiActivityPhase {
  idle,
  onboarding,
  waitingForReply,
  executingTool,
  receivingReply,
  revealingSegments,
}

class ConversationActivityPresentation {
  const ConversationActivityPresentation({
    required this.showLeftBubble,
    required this.showCenteredIndicator,
    this.label,
  });

  final bool showLeftBubble;
  final bool showCenteredIndicator;
  final String? label;
}

ConversationActivityPresentation conversationActivityPresentation(
  AiActivityPhase phase, {
  String? toolLabel,
}) {
  return switch (phase) {
    AiActivityPhase.onboarding ||
    AiActivityPhase.waitingForReply => const ConversationActivityPresentation(
      showLeftBubble: true,
      showCenteredIndicator: false,
    ),
    AiActivityPhase.executingTool => ConversationActivityPresentation(
      showLeftBubble: true,
      showCenteredIndicator: false,
      label: toolLabel == null ? '正在处理...' : '正在$toolLabel...',
    ),
    AiActivityPhase.idle ||
    AiActivityPhase.receivingReply ||
    AiActivityPhase.revealingSegments => const ConversationActivityPresentation(
      showLeftBubble: false,
      showCenteredIndicator: false,
    ),
  };
}

Duration segmentRevealDelay(String content) {
  final milliseconds = (1350 + content.runes.length * 55).clamp(1500, 2800);
  return Duration(milliseconds: milliseconds);
}
