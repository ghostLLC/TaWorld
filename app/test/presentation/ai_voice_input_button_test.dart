import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/presentation/screens/ai_home/ai_voice_input_button.dart';

void main() {
  testWidgets('idle voice button starts listening', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiVoiceInputButton(
            isListening: false,
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    expect(find.byTooltip('语音输入'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('语音输入'));
    expect(taps, 1);
  });

  testWidgets('listening state is clear and can be stopped', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiVoiceInputButton(isListening: true, onPressed: null),
        ),
      ),
    );

    expect(find.byTooltip('停止语音输入'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
  });
}
