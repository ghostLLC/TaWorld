import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/local/partner_service.dart';
import 'package:taworld/services/local/local_reminder_service.dart';
import 'package:taworld/services/local/local_user_service.dart';
import 'package:taworld/services/notification_service.dart';
import 'package:taworld/services/notification_ledger.dart';
import 'package:taworld/services/reminder_occurrence_service.dart';
import 'package:taworld/services/reminder_scheduler.dart';
import 'package:taworld/services/theme_service.dart';
import 'package:taworld/services/timezone_service.dart';
import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pending = <int, Map<Object?, Object?>>{};
  final calls = <String>[];
  setUp(() async {
    await openTestDatabase();
    SharedPreferences.setMockInitialValues({});
    await TimezoneService.initialize(
      identifierLoader: () async => 'Asia/Shanghai',
    );
    pending.clear();
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            calls.add(call.method);
            if (call.method == 'zonedSchedule') {
              final value = Map<Object?, Object?>.from(call.arguments as Map);
              pending[value['id'] as int] = value;
            }
            if (call.method == 'cancelAll') pending.clear();
            if (call.method == 'cancel') {
              pending.remove((call.arguments as Map)['id']);
            }
            if (call.method == 'pendingNotificationRequests') {
              return pending.values
                  .map(
                    (v) => {
                      'id': v['id'],
                      'title': v['title'],
                      'body': v['body'],
                      'payload': v['payload'],
                    },
                  )
                  .toList();
            }
            return true;
          },
        );
    await NotificationService.init();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await closeTestDatabase();
  });

  Future<void> seed() async {
    final person = await PartnerService.add(
      nickname: '妈妈',
      type: 'family',
      city: '北京',
    );
    await LocalReminderService.createConfig(
      partnerId: person.id,
      category: 'sleep',
    );
    await ReminderScheduler.scheduleAll();
  }

  test(
    'a terminated process lease cannot silently skip a new schedule',
    () async {
      final db = await DatabaseHelper.database;
      await db.insert('runtime_locks', {
        'name': 'reminder_schedule',
        'owner': 'legacy-process-token',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 2))
            .toIso8601String(),
      });
      await seed();
      expect(pending, isNotEmpty);
      expect(await db.query('runtime_locks'), isEmpty);
    },
  );

  test('resuming preserves notification IDs and never cancels all', () async {
    await seed();
    final original = pending.keys.toSet();
    final scheduledCalls = calls.where((c) => c == 'zonedSchedule').length;
    await ReminderScheduler.scheduleAll();
    expect(pending.keys.toSet(), original);
    expect(calls.where((c) => c == 'zonedSchedule').length, scheduledCalls);
    expect(calls, isNot(contains('cancelAll')));
  });

  test('a snoozed reminder survives foreground reconciliation', () async {
    await seed();
    final occurrence = (await ReminderOccurrenceService.getAll()).first;
    await NotificationService.respondToOccurrence(
      occurrence.id,
      ReminderNotificationAction.snooze,
    );
    final db = await DatabaseHelper.database;
    final snooze = (await db.query(
      'scheduled_notifications',
      where: "kind = 'snooze'",
    )).single;
    final id = snooze['notification_id'];
    await ReminderScheduler.scheduleAll();
    expect(pending.containsKey(id), isTrue);
    expect(
      (await ReminderOccurrenceService.getById(occurrence.id))!.status,
      'snoozed',
    );
  });

  test(
    'turning off notifications cancels schedules and blocks new ones',
    () async {
      await seed();
      expect(pending, isNotEmpty);
      await ThemeService.instance.setPushEnabled(false);
      expect(pending, isEmpty);
      await ReminderScheduler.scheduleAll();
      expect(pending, isEmpty);
    },
  );

  test(
    'three meals keep three independent history entries on one day',
    () async {
      final person = await PartnerService.add(nickname: '妈妈', type: 'family');
      final config = await LocalReminderService.createConfig(
        partnerId: person.id,
        category: 'meal',
      );
      final day = DateTime.now();
      for (final hour in [8, 12, 18]) {
        await LocalReminderService.createScheduledLog(
          configId: config.id,
          partnerId: person.id,
          message: '吃饭',
          scheduledTime: DateTime(day.year, day.month, day.day, hour),
        );
      }
      expect(
        await (await DatabaseHelper.database).query('reminder_logs'),
        hasLength(3),
      );
      expect((await LocalUserService.getStats())['streakDays'], 0);
    },
  );

  test('a disabled reminder is not a candidate for follow-up', () async {
    final person = await PartnerService.add(nickname: '妈妈', type: 'family');
    final config = await LocalReminderService.createConfig(
      partnerId: person.id,
      category: 'sleep',
    );
    await ReminderOccurrenceService.ensureScheduled(
      config: config,
      scheduledFor: DateTime.now().subtract(const Duration(minutes: 5)),
      message: '晚安',
    );
    await LocalReminderService.updateConfig(config.id, enabled: false);
    expect(await ReminderOccurrenceService.pendingFollowUps(), isEmpty);
  });

  test(
    'only observed evidence marks a notification as seen in the tray',
    () async {
      await seed();
      final occurrence = (await ReminderOccurrenceService.getAll()).first;
      await NotificationLedger.record(
        'posted_to_system',
        occurrenceId: occurrence.id,
      );
      expect(
        (await ReminderOccurrenceService.getById(occurrence.id))!.deliveredAt,
        isNull,
      );
      await NotificationLedger.record(
        'observed_in_tray',
        occurrenceId: occurrence.id,
      );
      expect(
        (await ReminderOccurrenceService.getById(occurrence.id))!.deliveredAt,
        isNotNull,
      );
      expect(
        (await ReminderOccurrenceService.getById(occurrence.id))!.status,
        'observed',
      );
    },
  );
}
