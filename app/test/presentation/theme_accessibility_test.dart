import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/app/design_tokens.dart';
import 'package:taworld/app/theme.dart';
import 'package:taworld/presentation/widgets/ta_achievement_badge.dart';
import 'package:taworld/presentation/widgets/ta_avatar.dart';
import 'package:taworld/presentation/widgets/ta_button.dart';
import 'package:taworld/presentation/widgets/ta_loading.dart';

double _contrastRatio(Color foreground, Color background) {
  double luminance(Color color) {
    final channels = [color.r, color.g, color.b].map((channel) {
      return channel <= 0.04045
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
    }).toList();
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  }

  final first = luminance(foreground);
  final second = luminance(background);
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('every light palette has readable semantic foregrounds', () {
    for (final palette in kTaPalettes) {
      for (final pair in [
        (palette.light.onPrimary, palette.light.primary, 'primary'),
        (palette.light.onSecondary, palette.light.secondary, 'secondary'),
        (palette.light.onTertiary, palette.light.tertiary, 'tertiary'),
      ]) {
        expect(
          _contrastRatio(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.id} ${pair.$3} foreground must remain readable',
        );
      }
    }
  });

  test('large card padding and radius follow the design hierarchy', () {
    expect(TaSpacing.cardInnerLarge, const EdgeInsets.all(24));
    expect(TaRadius.lg, 24);
  });

  testWidgets('icon button keeps a 48dp touch target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaIconButton(icon: Icons.close, onPressed: () {}),
        ),
      ),
    );

    final size = tester.getSize(find.byType(TaIconButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('dark avatar uses no light-mode shadow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TaTheme.dark,
        home: const Scaffold(body: TaAvatar(name: '小念')),
      ),
    );

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(TaAvatar),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('dark achievement badge uses the active dark scheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TaTheme.dark,
        home: const Scaffold(
          body: TaAchievementBadge(
            icon: 'badge',
            name: '测试成就',
            progress: 1,
            target: 1,
            unlocked: true,
          ),
        ),
      ),
    );

    final expected = TaTheme.dark.colorScheme.secondaryContainer;
    final matches = tester.widgetList<Container>(find.byType(Container)).any((
      container,
    ) {
      final decoration = container.decoration;
      return decoration is BoxDecoration && decoration.color == expected;
    });
    expect(matches, isTrue);
  });

  testWidgets('loading and celebration reduce motion when requested', (
    tester,
  ) async {
    const reduced = MediaQueryData(disableAnimations: true);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: reduced,
          child: TaLoading(message: '加载中'),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(TaLoading),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(data: reduced, child: TaCelebrateAnimation(size: 80)),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(TaCelebrateAnimation),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
    expect(find.byType(TaCelebrateAnimation), findsOneWidget);
  });
}
