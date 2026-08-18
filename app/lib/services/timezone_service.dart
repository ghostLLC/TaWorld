import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

typedef TimezoneIdentifierLoader = Future<String> Function();

/// Initializes the timezone database and selects the device's IANA timezone.
abstract final class TimezoneService {
  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  static Future<String> initialize({
    TimezoneIdentifierLoader? identifierLoader,
  }) async {
    _isInitialized = false;
    tz_data.initializeTimeZones();

    final identifier = identifierLoader != null
        ? await identifierLoader()
        : (await FlutterTimezone.getLocalTimezone()).identifier;

    final tz.Location location;
    try {
      location = tz.getLocation(identifier);
    } on tz.LocationNotFoundException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Unsupported device timezone: $identifier'),
        stackTrace,
      );
    }

    tz.setLocalLocation(location);
    _isInitialized = true;
    return identifier;
  }

  @visibleForTesting
  static void resetForTesting() {
    _isInitialized = false;
    tz.setLocalLocation(tz.UTC);
  }
}
