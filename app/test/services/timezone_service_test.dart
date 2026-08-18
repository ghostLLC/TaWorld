import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:taworld/services/timezone_service.dart';

void main() {
  tearDown(TimezoneService.resetForTesting);

  test('initializes the injected Asia/Shanghai location', () async {
    final identifier = await TimezoneService.initialize(
      identifierLoader: () async => 'Asia/Shanghai',
    );

    expect(identifier, 'Asia/Shanghai');
    expect(tz.local.name, 'Asia/Shanghai');
    expect(TimezoneService.isInitialized, isTrue);
  });

  test('uses daylight-saving offsets for America/Los_Angeles', () async {
    await TimezoneService.initialize(
      identifierLoader: () async => 'America/Los_Angeles',
    );

    final winter = tz.TZDateTime(tz.local, 2026, 1, 15);
    final summer = tz.TZDateTime(tz.local, 2026, 7, 15);

    expect(tz.local.name, 'America/Los_Angeles');
    expect(winter.timeZoneOffset, isNot(summer.timeZoneOffset));
    expect(winter.timeZoneOffset, const Duration(hours: -8));
    expect(summer.timeZoneOffset, const Duration(hours: -7));
  });

  test(
    'rejects an unsupported identifier without falling back to UTC',
    () async {
      const invalidIdentifier = 'Mars/Definitely_Not_A_Timezone';

      await expectLater(
        TimezoneService.initialize(
          identifierLoader: () async => invalidIdentifier,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(invalidIdentifier),
          ),
        ),
      );

      expect(TimezoneService.isInitialized, isFalse);
      expect(tz.local, same(tz.UTC));
    },
  );

  test(
    'marks initialization complete only after setting the location',
    () async {
      expect(TimezoneService.isInitialized, isFalse);

      await TimezoneService.initialize(
        identifierLoader: () async => 'Asia/Shanghai',
      );

      expect(TimezoneService.isInitialized, isTrue);
      expect(tz.local.name, 'Asia/Shanghai');
    },
  );

  test(
    'resetForTesting restores UTC and clears initialization state',
    () async {
      await TimezoneService.initialize(
        identifierLoader: () async => 'America/Los_Angeles',
      );
      expect(TimezoneService.isInitialized, isTrue);

      TimezoneService.resetForTesting();

      expect(TimezoneService.isInitialized, isFalse);
      expect(tz.local, same(tz.UTC));
    },
  );
}
