import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/ai_home/conversation_presentation.dart';

void main() {
  test('a user reply consumes the preceding choice prompt', () {
    final messages = [
      const ConversationMessageSnapshot(
        role: 'assistant',
        content: '是你的什么人呀\n[选项:家人|朋友|伴侣|同事]',
      ),
      const ConversationMessageSnapshot(role: 'user', content: '伴侣'),
    ];

    expect(findLatestUnansweredChoiceIndex(messages), isNull);
  });

  test('only the latest unanswered choice prompt remains interactive', () {
    final messages = [
      const ConversationMessageSnapshot(
        role: 'assistant',
        content: '第一个问题\n[选项:A|B]',
      ),
      const ConversationMessageSnapshot(role: 'assistant', content: '补充说明'),
      const ConversationMessageSnapshot(
        role: 'assistant',
        content: '第二个问题\n[选项:C|D]',
      ),
    ];

    expect(findLatestUnansweredChoiceIndex(messages), 2);
  });

  test('a new prompt after a reply can become interactive again', () {
    final messages = [
      const ConversationMessageSnapshot(
        role: 'assistant',
        content: '关系\n[选项:家人|朋友]',
      ),
      const ConversationMessageSnapshot(role: 'user', content: '家人'),
      const ConversationMessageSnapshot(
        role: 'assistant',
        content: '提醒时间\n[选项:早上|晚上]',
      ),
    ];

    expect(findLatestUnansweredChoiceIndex(messages), 2);
    expect(hasUserReplyAfter(messages, 0), isTrue);
    expect(hasUserReplyAfter(messages, 2), isFalse);
  });

  test(
    'onboarding replays only the actionable prompt until a partner exists',
    () {
      expect(
        planOnboardingEntry(hasPartners: false, introShown: false),
        OnboardingEntryPlan.introAndPrompt,
      );
      expect(
        planOnboardingEntry(hasPartners: false, introShown: true),
        OnboardingEntryPlan.promptOnly,
      );
      expect(
        planOnboardingEntry(hasPartners: true, introShown: true),
        OnboardingEntryPlan.none,
      );
    },
  );
}
