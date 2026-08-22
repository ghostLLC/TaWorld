import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/widgets/background_readiness_card.dart';
import 'package:taworld/services/background_execution_service.dart';

void main() {
  testWidgets(
    'shows verifiable statuses without claiming autostart permission',
    (tester) async {
      const readiness = BackgroundExecutionReadiness(
        notificationGranted: false,
        exactAlarmAllowed: false,
        batteryOptimizationIgnored: false,
        autoStartGuidanceAvailable: true,
        autoStartStatusKnown: false,
        manufacturer: 'Xiaomi',
        bestEffort: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackgroundReadinessCard(
                readiness: readiness,
                onOpenNotifications: () {},
                onOpenExactAlarms: () {},
                onOpenBattery: () {},
                onOpenAutoStart: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('后台提醒保障'), findsOneWidget);
      expect(find.textContaining('尽力送达'), findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
      expect(find.text('精确定时'), findsOneWidget);
      expect(find.text('电池无限制'), findsOneWidget);
      expect(find.text('自启动'), findsOneWidget);
      expect(find.text('未开启'), findsNWidgets(3));
      expect(find.text('需在系统中确认'), findsOneWidget);
      expect(find.textContaining('无法替你开启'), findsOneWidget);
    },
  );
}
