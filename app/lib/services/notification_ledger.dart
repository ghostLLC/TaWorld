import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';
import 'native_notification_bridge.dart';

/// Local facts, not an inference that the user read or acted on a notification.
abstract final class NotificationLedger {
  static String fingerprint({
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) => jsonEncode({
    'title': title,
    'body': body,
    'at': at.toUtc().millisecondsSinceEpoch,
    'payload': payload,
  });

  static Future<void> rememberSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
    String kind = 'regular',
  }) async {
    final occurrenceId = _occurrenceId(payload);
    if (occurrenceId == null) return;
    final db = await DatabaseHelper.database;
    await db.insert('scheduled_notifications', {
      'notification_id': id,
      'occurrence_id': occurrenceId,
      'scheduled_for': at.toUtc().toIso8601String(),
      'kind': kind,
      'fingerprint': fingerprint(
        title: title,
        body: body,
        at: at,
        payload: payload,
      ),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> record(
    String kind, {
    String? occurrenceId,
    int? notificationId,
    String? detail,
    DateTime? at,
  }) async {
    final db = await DatabaseHelper.database;
    await db.transaction(
      (tx) => _apply(tx, {
        'id': DatabaseHelper.newId(),
        'kind': kind,
        'occurrence_id': occurrenceId,
        'notification_id': notificationId,
        'detail': detail,
        'occurred_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      }),
    );
  }

  static Future<void> consumeNativeEvents() async {
    final events = await NativeNotificationBridge.records('events');
    if (events == null || events.isEmpty) return;
    final db = await DatabaseHelper.database;
    await db.transaction((tx) async {
      for (final event in events) {
        await _apply(tx, {
          'id': event['id'],
          'kind': event['kind'],
          'occurrence_id': _occurrenceId(event['payload'] as String?),
          'notification_id': event['notificationId'],
          'detail': event['detail'],
          'occurred_at': DateTime.fromMillisecondsSinceEpoch(
            event['at'] as int,
            isUtc: true,
          ).toIso8601String(),
        });
      }
    });
    // A failed acknowledgement is safe: primary keys deduplicate the next read.
    await NativeNotificationBridge.invoke<bool>(
      'ackEvents',
      events.map((e) => e['id']).toList(),
    );
  }

  static Future<void> _apply(Transaction tx, Map<String, Object?> event) async {
    final existing = await tx.query(
      'notification_events',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [event['id']],
    );
    if (existing.isNotEmpty) return;
    await tx.insert('notification_events', event);
    final id = event['occurrence_id'];
    if (id == null) return;
    final kind = event['kind'];
    final at = event['occurred_at'];
    if (const {
      'blocked_permission',
      'publish_failed',
      'historical_unknown',
    }.contains(kind)) {
      await tx.update(
        'reminder_occurrences',
        {
          'status': kind == 'historical_unknown' ? 'unknown' : 'blocked',
          'updated_at': at,
        },
        where: "id = ? AND status IN ('scheduled', 'snoozed', 'posted')",
        whereArgs: [id],
      );
    }
    if (kind == 'observed_in_tray' || kind == 'posted_to_system') {
      await tx.update(
        'reminder_occurrences',
        {
          'status': kind == 'observed_in_tray' ? 'observed' : 'posted',
          if (kind == 'observed_in_tray') 'delivered_at': at,
          'updated_at': at,
        },
        where: "id = ? AND status IN ('scheduled', 'posted', 'snoozed')",
        whereArgs: [id],
      );
      if (kind == 'observed_in_tray') {
        await tx.update(
          'reminder_logs',
          {'status': 'sent', 'sent_at': at},
          where: "occurrence_id = ? AND status = 'scheduled'",
          whereArgs: [id],
        );
      }
    } else if (kind == 'action_done' ||
        kind == 'action_snooze' ||
        kind == 'action_outdated') {
      final snoozedUntil = kind == 'action_snooze'
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(event['detail'] as String),
              isUtc: true,
            ).toIso8601String()
          : null;
      await tx.update(
        'reminder_occurrences',
        {
          'status': kind == 'action_done'
              ? 'acknowledged'
              : kind == 'action_snooze'
              ? 'snoozed'
              : 'dismissed',
          'response': (kind as String).substring('action_'.length),
          'responded_at': at,
          'snoozed_until': snoozedUntil,
          'updated_at': at,
        },
        where: "id = ? AND status != 'cancelled'",
        whereArgs: [id],
      );
      if (kind == 'action_done') {
        await tx.update(
          'reminder_logs',
          {'status': 'confirmed', 'confirmed_at': at},
          where: 'occurrence_id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  static String? _occurrenceId(String? payload) =>
      payload?.startsWith('occurrenceId:') == true
      ? payload!.substring('occurrenceId:'.length)
      : null;
}
