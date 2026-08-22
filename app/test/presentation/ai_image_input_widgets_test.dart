import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/presentation/screens/ai_home/ai_image_input_button.dart';
import 'package:taworld/presentation/screens/ai_home/chat_image_bubble.dart';

void main() {
  testWidgets('image button exposes a compact picker action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiImageInputButton(onPressed: () => taps++)),
      ),
    );

    expect(find.byTooltip('发送图片'), findsOneWidget);
    await tester.tap(find.byTooltip('发送图片'));
    expect(taps, 1);
  });

  testWidgets('missing local file has a calm fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatImageBubble(localPath: 'missing.png', summary: '旧图片记录'),
        ),
      ),
    );

    expect(find.text('图片文件暂不可用'), findsOneWidget);
    expect(find.text('旧图片记录'), findsOneWidget);
    expect(tester.getSize(find.byType(ChatImageBubble)).width, 288);
  });
}
