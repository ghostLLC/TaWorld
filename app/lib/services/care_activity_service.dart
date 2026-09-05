import '../data/local/database_helper.dart';

/// Counts explicit acknowledgements in the user's local calendar, accepting
/// both legacy local timestamps and new UTC event timestamps.
abstract final class CareActivityService {
  static Future<int> streakDays({DateTime? now}) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_logs',
      columns: ['confirmed_at'],
      where: "status = 'confirmed' AND confirmed_at IS NOT NULL",
    );
    return streakFromTimestamps(
      rows.map((r) => r['confirmed_at'] as String),
      now: now ?? DateTime.now(),
    );
  }

  static int streakFromTimestamps(
    Iterable<String> timestamps, {
    required DateTime now,
  }) {
    String key(DateTime time) => '${time.year}-${time.month}-${time.day}';
    final dates = timestamps
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .map((d) => key(d.toLocal()))
        .toSet();
    final today = now.toLocal();
    var count = 0;
    for (var offset = 0; offset < 366; offset++) {
      final day = DateTime(today.year, today.month, today.day - offset);
      if (!dates.contains(key(day))) break;
      count++;
    }
    return count;
  }
}
