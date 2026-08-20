import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/services/stale_while_revalidate_cache.dart';

void main() {
  test('concurrent cache misses share one loader request', () async {
    final completer = Completer<String?>();
    var loadCount = 0;
    final cache = StaleWhileRevalidateCache<String, String>(
      ttl: const Duration(minutes: 10),
    );

    Future<String?> loader() {
      loadCount++;
      return completer.future;
    }

    final first = cache.get('广州', loader);
    final second = cache.get('广州', loader);
    expect(loadCount, 1);

    completer.complete('晴 30°C');
    expect(await first, '晴 30°C');
    expect(await second, '晴 30°C');
  });

  test('stale value is returned while one background refresh runs', () async {
    var now = DateTime.utc(2026, 8, 20, 12);
    var value = '晴 30°C';
    var loadCount = 0;
    final refreshCompleter = Completer<String?>();
    final cache = StaleWhileRevalidateCache<String, String>(
      ttl: const Duration(minutes: 10),
      clock: () => now,
    );

    Future<String?> loader() {
      loadCount++;
      if (loadCount == 1) return Future.value(value);
      return refreshCompleter.future;
    }

    expect(await cache.get('广州', loader), value);
    now = now.add(const Duration(minutes: 11));

    expect(await cache.get('广州', loader), '晴 30°C');
    expect(await cache.get('广州', loader), '晴 30°C');
    expect(loadCount, 2);

    value = '雨 26°C';
    refreshCompleter.complete(value);
    await Future<void>.delayed(Duration.zero);

    expect(await cache.get('广州', loader), '雨 26°C');
    expect(loadCount, 2);
  });

  test('explicit refresh bypasses a still-fresh cached value', () async {
    var loadCount = 0;
    final cache = StaleWhileRevalidateCache<String, String>(
      ttl: const Duration(minutes: 10),
    );

    Future<String?> loader() async => 'value-${++loadCount}';

    expect(await cache.get('广州', loader), 'value-1');
    expect(await cache.get('广州', loader), 'value-1');
    expect(await cache.refresh('广州', loader), 'value-2');
    expect(await cache.get('广州', loader), 'value-2');
  });
}
