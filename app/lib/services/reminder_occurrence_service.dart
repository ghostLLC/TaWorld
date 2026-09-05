import '../data/local/database_helper.dart';
import '../data/models/reminder_config.dart';
import '../data/models/reminder_occurrence_record.dart';

enum ReminderUserResponse { done, snooze, outdated }

extension ReminderUserResponseWireName on ReminderUserResponse {
  String get wireName => switch (this) {
    ReminderUserResponse.done => 'done',
    ReminderUserResponse.snooze => 'snooze',
    ReminderUserResponse.outdated => 'outdated',
  };
}

abstract final class ReminderOccurrenceService {
  static Future<ReminderOccurrenceRecord> ensureScheduled({
    required ReminderConfig config,
    required DateTime scheduledFor,
    required String message,
  }) async {
    final db = await DatabaseHelper.database;
    final instant = scheduledFor.toUtc().toIso8601String();
    final existing = await db.query(
      'reminder_occurrences',
      where: 'config_id = ? AND scheduled_for = ?',
      whereArgs: [config.id, instant],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final row = existing.single;
      if (row['status'] == 'cancelled' &&
          config.enabled &&
          scheduledFor.isAfter(DateTime.now())) {
        await db.update(
          'reminder_occurrences',
          {
            'status': 'scheduled',
            'message': message,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        return (await getById(row['id'] as String))!;
      }
      return ReminderOccurrenceRecord.fromMap(row);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final id = DatabaseHelper.newId();
    await db.insert('reminder_occurrences', {
      'id': id,
      'config_id': config.id,
      'subject_kind': config.subjectKind,
      'subject_id': config.subjectId,
      'status': 'scheduled',
      'scheduled_for': instant,
      'message': message,
      'created_at': now,
      'updated_at': now,
    });
    return (await getById(id))!;
  }

  static Future<ReminderOccurrenceRecord?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_occurrences',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ReminderOccurrenceRecord.fromMap(rows.single);
  }

  static Future<List<ReminderOccurrenceRecord>> getAll() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_occurrences',
      orderBy: 'scheduled_for ASC',
    );
    return rows.map(ReminderOccurrenceRecord.fromMap).toList();
  }

  static Future<ReminderOccurrenceRecord> respond(
    String id,
    ReminderUserResponse response, {
    DateTime? now,
    Duration snoozeDuration = const Duration(minutes: 5),
  }) async {
    final db = await DatabaseHelper.database;
    final responseTime = (now ?? DateTime.now()).toUtc();
    final status = switch (response) {
      ReminderUserResponse.done => 'acknowledged',
      ReminderUserResponse.snooze => 'snoozed',
      ReminderUserResponse.outdated => 'dismissed',
    };
    final current = await getById(id);
    if (current == null) throw StateError('Reminder occurrence not found');
    if (current.status == 'acknowledged' ||
        current.status == 'dismissed' ||
        current.status == 'cancelled') {
      return current;
    }
    if (response == ReminderUserResponse.snooze &&
        current.snoozedUntil?.isAfter(responseTime) == true) {
      return current;
    }
    final updated = await db.update(
      'reminder_occurrences',
      {
        'status': status,
        'response': response.wireName,
        'responded_at': responseTime.toIso8601String(),
        'snoozed_until': response == ReminderUserResponse.snooze
            ? responseTime.add(snoozeDuration).toIso8601String()
            : null,
        'updated_at': responseTime.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated != 1) throw StateError('Reminder occurrence not found: $id');
    return (await getById(id))!;
  }

  static Future<List<ReminderOccurrenceRecord>> pendingFollowUps({
    DateTime? now,
    int limit = 3,
  }) async {
    final db = await DatabaseHelper.database;
    final current = (now ?? DateTime.now()).toUtc();
    final instant = current.toIso8601String();
    final earliest = current
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    final rows = await db.query(
      'reminder_occurrences',
      where:
          "((status IN ('scheduled', 'posted', 'observed') AND scheduled_for <= ?) OR "
          "(status = 'snoozed' AND snoozed_until <= ?)) "
          "AND scheduled_for >= ? AND EXISTS (SELECT 1 FROM reminder_configs c "
          "WHERE c.id = reminder_occurrences.config_id AND c.enabled = 1 "
          "AND (c.subject_kind = 'user' OR EXISTS (SELECT 1 FROM partners p "
          "WHERE p.id = c.partner_id AND p.status = 'active')))",
      whereArgs: [instant, instant, earliest],
      orderBy: 'scheduled_for ASC',
      limit: limit,
    );
    return rows.map(ReminderOccurrenceRecord.fromMap).toList();
  }
}
