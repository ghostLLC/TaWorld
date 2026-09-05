import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:taworld/app/theme.dart';
import 'package:taworld/data/models/partner.dart';
import 'package:taworld/data/models/reminder_config.dart';
import 'package:taworld/presentation/screens/home/care_graph_view.dart';
import 'package:taworld/services/weather_service.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  final partner = Partner(
    id: 'partner-singapore',
    nickname: '小乐',
    type: 'partner',
    city: '新加坡',
    timezoneId: 'Asia/Singapore',
    timezoneConfirmed: true,
    status: 'active',
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
  );

  const weather = FullWeatherResult(
    current: WeatherResult(text: '多云', temp: 29),
    sourceTimezoneId: 'Asia/Singapore',
    forecast: [],
  );

  testWidgets(
    'overview keeps context and selection shows weather and temperature',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        _GraphHarness(
          partner: partner,
          weatherByPartner: {partner.id: weather},
        ),
      );

      expect(find.textContaining('新加坡'), findsWidgets);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('小乐'));
      await tester.pumpAndSettle();
      expect(find.textContaining('多云 · 29°C'), findsOneWidget);
      expect(find.byTooltip('全屏查看图谱'), findsOneWidget);
      expect(find.byTooltip('分享关心图谱'), findsOneWidget);
      expect(find.textContaining('人物节点同尺寸'), findsNothing);
    },
  );

  testWidgets('overview exposes reminder count beside the person node', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final config = ReminderConfig(
      id: 'reminder-1',
      partnerId: partner.id,
      category: 'sleep',
      enabled: true,
      config: const {'target_sleep_time': '23:00', 'advance_minutes': 30},
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    await tester.pumpWidget(_GraphHarness(partner: partner, configs: [config]));

    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('小乐'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 个提醒'), findsOneWidget);
  });

  testWidgets('fullscreen graph is immersive and keeps only the exit control', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _GraphHarness(partner: partner, weatherByPartner: {partner.id: weather}),
    );

    await tester.tap(find.byTooltip('全屏查看图谱'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('care-graph-fullscreen-close')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('care-graph-fullscreen-interactive')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('care-graph-fullscreen-interactive')))
          .width,
      390,
      reason:
          'The fullscreen canvas must fill the phone, not shrink to its exit button.',
    );
    expect(find.byTooltip('分享关心图谱'), findsNothing);
    expect(find.byType(AppBar), findsNothing);

    await tester.tap(find.byKey(const Key('care-graph-fullscreen-close')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('全屏查看图谱'), findsOneWidget);
  });

  testWidgets('selected partner exposes one prominent chat action', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    Partner? requestedPartner;
    await tester.pumpWidget(
      _GraphHarness(
        partner: partner,
        onChatPartner: (value) => requestedPartner = value,
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('小乐'));
    await tester.pumpAndSettle();

    final chatAction = find.widgetWithText(FilledButton, '聊聊Ta');
    expect(chatAction, findsOneWidget);
    expect(find.text('伴侣'), findsWidgets);
    expect(find.text('档案'), findsOneWidget);
    expect(find.byKey(const Key('care-graph-interactive')), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);

    await tester.ensureVisible(chatAction);
    await tester.pumpAndSettle();
    await tester.tap(chatAction);
    expect(requestedPartner, same(partner));
  });

  testWidgets('missing weather uses an honest loading or unavailable label', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      _GraphHarness(partner: partner, weatherLoadingIds: {partner.id}),
    );

    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('小乐'));
    await tester.pumpAndSettle();
    expect(find.textContaining('天气更新中'), findsOneWidget);
  });

  testWidgets('graph remains overflow-free on a 390 by 844 phone viewport', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _GraphHarness(partner: partner, weatherByPartner: {partner.id: weather}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('小乐'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('聊聊Ta'), findsOneWidget);
  });
  testWidgets(
    'selected actions remain usable in dark mode at 200 percent text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        _GraphHarness(partner: partner, dark: true, textScale: 2),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('小乐'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('聊聊Ta'), findsOneWidget);
      expect(find.text('档案'), findsOneWidget);
    },
  );
}

class _GraphHarness extends StatelessWidget {
  const _GraphHarness({
    required this.partner,
    this.weatherByPartner = const {},
    this.weatherLoadingIds = const {},
    this.onChatPartner,
    this.configs = const [],
    this.dark = false,
    this.textScale = 1,
  });

  final bool dark;
  final double textScale;
  final Partner partner;
  final Map<String, FullWeatherResult?> weatherByPartner;
  final Set<String> weatherLoadingIds;
  final ValueChanged<Partner>? onChatPartner;
  final List<ReminderConfig> configs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: dark ? TaTheme.dark : TaTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: CareGraphView(
            partners: [partner],
            weatherByPartner: weatherByPartner,
            weatherLoadingIds: weatherLoadingIds,
            configsByPartner: {partner.id: configs},
            onChatPartner: onChatPartner ?? (_) {},
            onAddReminder: (_) {},
            onOpenProfile: (_) {},
          ),
        ),
      ),
    );
  }
}
