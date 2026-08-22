import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/presentation/screens/ai_home/retry_message_card.dart';

void main() {
  testWidgets('network failure offers one calm retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RetryMessageCard(onRetry: () => retried = true)),
      ),
    );

    expect(find.text('刚才没有连上网络'), findsOneWidget);
    expect(find.text('你的消息还在，连接恢复后可以继续'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    expect(retried, isTrue);
  });
}
