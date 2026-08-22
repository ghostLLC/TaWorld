import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/ai_home/conversation_activity.dart';

void main() {
  test('waiting and onboarding use a quiet left activity bubble', () {
    for (final phase in [
      AiActivityPhase.onboarding,
      AiActivityPhase.waitingForReply,
    ]) {
      final presentation = conversationActivityPresentation(phase);

      expect(presentation.showLeftBubble, isTrue);
      expect(presentation.label, isNull);
      expect(presentation.showCenteredIndicator, isFalse);
    }
  });

  test('tool execution stays in the left bubble with an operation label', () {
    final presentation = conversationActivityPresentation(
      AiActivityPhase.executingTool,
      toolLabel: '创建提醒',
    );

    expect(presentation.showLeftBubble, isTrue);
    expect(presentation.label, '正在创建提醒...');
    expect(presentation.showCenteredIndicator, isFalse);
  });

  test('receiving and segmented reveal never render thinking indicators', () {
    for (final phase in [
      AiActivityPhase.receivingReply,
      AiActivityPhase.revealingSegments,
      AiActivityPhase.idle,
    ]) {
      final presentation = conversationActivityPresentation(phase);

      expect(presentation.showLeftBubble, isFalse);
      expect(presentation.showCenteredIndicator, isFalse);
    }
  });

  test('segment reveal pauses are natural and bounded', () {
    expect(segmentRevealDelay('好呀'), const Duration(milliseconds: 1500));
    expect(
      segmentRevealDelay(List.filled(80, '字').join()),
      const Duration(milliseconds: 2800),
    );
  });
}
