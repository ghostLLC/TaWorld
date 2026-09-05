import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taworld/app/theme.dart';
import 'package:taworld/presentation/screens/settings/settings_screen.dart';
import 'package:taworld/services/theme_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
    await ThemeService.instance.init();
  });

  testWidgets('settings exposes light system and dark modes on the root page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: TaTheme.light, home: const SettingsScreen()),
    );

    final selector = find.byKey(const Key('settings-theme-mode-selector'));
    expect(selector, findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(ThemeService.instance.mode, ThemeMode.dark);
  });
}
