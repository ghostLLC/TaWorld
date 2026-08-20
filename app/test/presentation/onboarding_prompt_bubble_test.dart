import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/ai_home/onboarding_prompt_bubble.dart';

void main() {
  testWidgets('inline onboarding input focuses and submits its value', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    String? submitted;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingPromptBubble(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (value) => submitted = value,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('先来告诉我一个你在意的人吧：'), findsOneWidget);
    expect(focusNode.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), '小乐');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(submitted, '小乐');
  });
}
