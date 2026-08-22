import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/ai_home/ai_quick_action_chip.dart';

void main() {
  testWidgets(
    'quick action keeps text before icon and a comfortable tap area',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AiQuickActionChip(
                label: '写句晚安语',
                icon: Icons.bedtime_rounded,
                iconColor: Colors.indigo,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      final label = find.text('写句晚安语');
      final icon = find.byIcon(Icons.bedtime_rounded);
      expect(tester.getCenter(label).dx, lessThan(tester.getCenter(icon).dx));
      expect(tester.getSize(find.byType(AiQuickActionChip)).height, 48);
    },
  );
}
