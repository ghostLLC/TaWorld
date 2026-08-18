import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:taworld/services/notification_service.dart';
import 'package:taworld/services/timezone_service.dart';

void main() {
  tearDown(TimezoneService.resetForTesting);

  test('notification readiness is false before notification initialization', () {
    expect(NotificationService.isInitialized, isFalse);
  });

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

  test('concurrent initialization shares the first in-flight result', () async {
    final loaderStarted = Completer<void>();
    final releaseLoader = Completer<void>();
    var loaderCalls = 0;

    Future<String> firstLoader() async {
      loaderCalls++;
      loaderStarted.complete();
      await releaseLoader.future;
      return 'Asia/Shanghai';
    }

    final firstInitialization = TimezoneService.initialize(
      identifierLoader: firstLoader,
    );
    await loaderStarted.future;

    final secondInitialization = TimezoneService.initialize(
      identifierLoader: () async {
        loaderCalls++;
        return 'America/Los_Angeles';
      },
    );
    releaseLoader.complete();

    expect(await firstInitialization, 'Asia/Shanghai');
    expect(await secondInitialization, 'Asia/Shanghai');
    expect(loaderCalls, 1);
    expect(tz.local.name, 'Asia/Shanghai');
  });

  test('failed initialization clears in-flight state for a successful retry',
      () async {
    var loaderCalls = 0;

    await expectLater(
      TimezoneService.initialize(
        identifierLoader: () async {
          loaderCalls++;
          throw StateError('temporary timezone discovery failure');
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(TimezoneService.isInitialized, isFalse);

    final identifier = await TimezoneService.initialize(
      identifierLoader: () async {
        loaderCalls++;
        return 'Asia/Shanghai';
      },
    );

    expect(identifier, 'Asia/Shanghai');
    expect(loaderCalls, 2);
    expect(TimezoneService.isInitialized, isTrue);
    expect(tz.local.name, 'Asia/Shanghai');
  });
}
