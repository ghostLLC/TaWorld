/// Immutable message data used to derive presentation-only conversation state.
class ConversationMessageSnapshot {
  const ConversationMessageSnapshot({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;
}

final RegExp choiceMarkerPattern = RegExp(r'\[选项:([^\]]+)\]');

/// Splits the model's conversational `|||` cadence while keeping a standalone
/// choice marker attached to the question immediately before it.
List<String> splitAssistantPresentationSegments(String content) {
  final rawParts = content
      .split('|||')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  final parts = <String>[];
  for (final part in rawParts) {
    final marker = choiceMarkerPattern.firstMatch(part);
    final isMarkerOnly = marker != null && marker.group(0) == part;
    if (isMarkerOnly && parts.isNotEmpty) {
      parts[parts.length - 1] = '${parts.last}\n$part';
    } else {
      parts.add(part);
    }
  }
  return parts;
}

enum OnboardingEntryPlan { none, introAndPrompt, promptOnly }

OnboardingEntryPlan planOnboardingEntry({
  required bool hasPartners,
  required bool introShown,
}) {
  if (hasPartners) return OnboardingEntryPlan.none;
  return introShown
      ? OnboardingEntryPlan.promptOnly
      : OnboardingEntryPlan.introAndPrompt;
}

/// Returns the index of the latest choice prompt that has not been followed by
/// a user message. Persisted message content is never mutated.
int? findLatestUnansweredChoiceIndex(
  List<ConversationMessageSnapshot> messages,
) {
  int? pendingIndex;
  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    if (message.role == 'user') {
      pendingIndex = null;
    } else if (choiceMarkerPattern.hasMatch(message.content)) {
      pendingIndex = index;
    }
  }
  return pendingIndex;
}

/// Whether a prompt at [messageIndex] has already received a user reply.
bool hasUserReplyAfter(
  List<ConversationMessageSnapshot> messages,
  int messageIndex,
) {
  if (messageIndex < 0 || messageIndex >= messages.length) return false;
  return messages
      .skip(messageIndex + 1)
      .any((message) => message.role == 'user');
}
