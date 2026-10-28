import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taworld/data/models/partner.dart';
import 'package:taworld/services/care_suggestion_service.dart';
import 'package:taworld/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'local care suggestions use neutral names instead of assumed gender',
    () async {
      final partner = Partner(
        id: 'partner-1',
        nickname: '小乐',
        type: 'family',
        status: 'active',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      );
      const weather = WeatherResult(text: '小雨', temp: 8);

      for (var index = 0; index < 20; index++) {
        final suggestion = await CareSuggestionService.generate(
          partner: partner,
          configs: const [],
          weather: weather,
        );
        expect(suggestion, isNot(contains('她')));
      }
    },
  );
}
