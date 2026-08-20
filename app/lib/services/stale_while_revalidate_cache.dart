import 'dart:async';

typedef CacheClock = DateTime Function();

class _CacheEntry<V> {
  const _CacheEntry(this.value, this.loadedAt);

  final V value;
  final DateTime loadedAt;
}

/// Small in-memory stale-while-revalidate cache with request de-duplication.
class StaleWhileRevalidateCache<K, V extends Object> {
  StaleWhileRevalidateCache({required this.ttl, CacheClock? clock})
    : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final CacheClock _clock;
  final Map<K, _CacheEntry<V>> _entries = {};
  final Map<K, Future<V?>> _inFlight = {};

  Future<V?> get(K key, Future<V?> Function() loader) {
    final entry = _entries[key];
    if (entry != null) {
      final isFresh = _clock().difference(entry.loadedAt) < ttl;
      if (isFresh) return Future.value(entry.value);
      unawaited(_refresh(key, loader));
      return Future.value(entry.value);
    }
    return _refresh(key, loader);
  }

  /// Bypasses freshness while still joining an already-running request.
  Future<V?> refresh(K key, Future<V?> Function() loader) {
    return _refresh(key, loader);
  }

  Future<V?> _refresh(K key, Future<V?> Function() loader) {
    final running = _inFlight[key];
    if (running != null) return running;

    late final Future<V?> request;
    request = loader()
        .then((value) {
          if (value != null) {
            _entries[key] = _CacheEntry(value, _clock());
          }
          return value;
        })
        .whenComplete(() {
          if (identical(_inFlight[key], request)) {
            _inFlight.remove(key);
          }
        });
    _inFlight[key] = request;
    return request;
  }

  void clear() {
    _entries.clear();
  }
}
