import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taworld/services/local/local_reminder_service.dart';
import 'package:taworld/services/local/partner_service.dart';
import 'package:taworld/services/partner_selection.dart';
import 'package:taworld/services/reminder_tool_planner.dart';
import 'package:taworld/services/reminder_schedule_calculator.dart';
import 'package:taworld/services/reminder_edit_service.dart';
import 'package:taworld/services/tool_operation_journal.dart';
import 'package:taworld/services/ai_proactive_service.dart';
import 'package:taworld/services/ai_memory_service.dart';
import 'package:taworld/services/timezone_service.dart';
import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await openTestDatabase();
    SharedPreferences.setMockInitialValues({});
    await TimezoneService.initialize(
      identifierLoader: () async => 'Asia/Shanghai',
    );
  });
  tearDown(closeTestDatabase);

  test(
    'same-name people require an ID; ID resolves the intended person',
    () async {
      await PartnerService.add(nickname: '小林', type: 'friend', city: '北京');
      final second = await PartnerService.add(
        nickname: '小林',
        type: 'colleague',
        city: '上海',
      );
      final people = await PartnerService.getAll();
      expect(
        () => PartnerSelection.resolve(people, name: '小林'),
        throwsStateError,
      );
      expect(PartnerSelection.resolve(people, id: second.id).city, '上海');
    },
  );
  test(
    'relative single reminder remains one fixed instant after resume',
    () async {
      final now = DateTime.utc(2026, 9, 5, 4);
      final plan = ReminderToolPlanner.parse({
        'subject': 'self',
        'category': 'custom',
        'message': '喝水',
        'relative_minutes': 10,
      }, now: now).plan!;
      final config = await LocalReminderService.createConfig(
        category: 'custom',
        config: plan.config,
        subjectKind: 'user',
        subjectId: 'self',
      );
      final occurrences = ReminderScheduleCalculator.build(
        config: config,
        partnerName: '自己',
        now: tz.TZDateTime.from(now, tz.local),
      );
      expect(occurrences, hasLength(1));
      expect(
        occurrences.single.scheduledTime.toUtc(),
        now.add(const Duration(minutes: 10)),
      );
      expect(
        ReminderScheduleCalculator.build(
          config: config,
          partnerName: '自己',
          now: tz.TZDateTime.from(
            now.add(const Duration(minutes: 11)),
            tz.local,
          ),
        ),
        isEmpty,
      );
    },
  );
  test(
    'weekday custom reminders skip weekends and retain calendar wall time',
    () async {
      final config = await LocalReminderService.createConfig(
        category: 'custom',
        subjectKind: 'user',
        subjectId: 'self',
        config: {
          'message': '问候',
          'target_time': '09:00',
          'repeat_daily': true,
          'weekdays': [1, 2, 3, 4, 5],
        },
      );
      final occurrences = ReminderScheduleCalculator.build(
        config: config,
        partnerName: '自己',
        now: tz.TZDateTime(tz.local, 2026, 9, 5, 10),
      );
      expect(occurrences, hasLength(7));
      expect(occurrences.first.scheduledTime.day, 7);
      expect(
        occurrences.every(
          (o) => o.scheduledTime.weekday <= 5 && o.scheduledTime.hour == 9,
        ),
        isTrue,
      );
    },
  );
  test('absolute dates without offset and expired dates are rejected', () {
    for (final at in ['2026-09-06T09:00:00', '2026-09-04T09:00:00+08:00']) {
      expect(
        ReminderToolPlanner.parse({
          'subject': 'self',
          'category': 'custom',
          'message': '问候',
          'scheduled_at': at,
        }, now: DateTime.utc(2026, 9, 5)).plan,
        isNull,
      );
    }
  });
  test(
    'editing one meal preserves other meals; pause and resume preserve data',
    () async {
      final person = await PartnerService.add(nickname: '妈妈', type: 'family');
      final config = await LocalReminderService.createConfig(
        partnerId: person.id,
        category: 'meal',
      );
      final changed = await ReminderEditService.update({
        'reminder_id': config.id,
        'meal_name': '午餐',
        'time': '12:30',
      });
      final meals = changed.config['meals'] as List;
      expect(meals[0]['target_time'], '08:00');
      expect(meals[1]['target_time'], '12:30');
      expect(meals[2]['target_time'], '18:00');
      final paused = await ReminderEditService.update({
        'reminder_id': config.id,
        'enabled': false,
      });
      expect(paused.enabled, isFalse);
      final resumed = await ReminderEditService.update({
        'reminder_id': config.id,
        'enabled': true,
      });
      expect(resumed.enabled, isTrue);
      expect(resumed.config, changed.config);
    },
  );
  test(
    'retrying the same mutation with reordered args reuses the receipt',
    () async {
      var mutations = 0;
      Future<String> perform(Map<String, dynamic> args) =>
          ToolOperationJournal.execute(
            requestId: 'request1',
            tool: 'create_partner',
            arguments: args,
            action: () async {
              mutations++;
              return jsonEncode({
                'status': 'success',
                'verified': true,
                'entity_id': 'p1',
              });
            },
          );
      expect(
        await perform({'name': '妈妈', 'city': '北京'}),
        await perform({'city': '北京', 'name': '妈妈'}),
      );
      expect(mutations, 1);
    },
  );
  test(
    'interruption after starting a write never blindly repeats the write',
    () async {
      var mutations = 0;
      Future<String> execute() => ToolOperationJournal.execute(
        requestId: 'interrupted',
        tool: 'create_reminder',
        arguments: {'time': '09:00'},
        action: () async {
          mutations++;
          throw StateError('interrupted');
        },
      );
      await expectLater(execute(), throwsStateError);
      expect(jsonDecode(await execute())['verified'], isFalse);
      expect(mutations, 1);
    },
  );
  test('proactive replies cannot invent a recipient or confidence', () {
    final base = <String, dynamic>{
      'partner_id': 'p1',
      'category': 'weather',
      'message': '记得带伞',
      'confidence': 0.8,
    };
    expect(AiProactiveService.validCandidateResponse(base, {'p1'}), isTrue);
    expect(
      AiProactiveService.validCandidateResponse(
        {...base, 'partner_id': 'unknown'},
        {'p1'},
      ),
      isFalse,
    );
    expect(
      AiProactiveService.validCandidateResponse(
        {...base, 'confidence': double.nan},
        {'p1'},
      ),
      isFalse,
    );
  });
  test(
    'prompt includes precise clock, IDs and self reminders without relationship inference',
    () async {
      final person = await PartnerService.add(
        nickname: '妈妈',
        type: 'family',
        city: '广州',
      );
      final reminder = await LocalReminderService.createConfig(
        category: 'custom',
        subjectKind: 'user',
        subjectId: 'self',
        config: {'message': '喝水', 'repeat_daily': true, 'target_time': '09:00'},
      );
      final prompt = await AiMemoryService.buildSystemPrompt();
      expect(prompt, contains(person.id));
      expect(prompt, contains(reminder.id));
      expect(prompt, contains('Asia/Shanghai'));
      expect(prompt, contains('weekday'));
      expect(prompt, contains('update_reminder'));
      expect(prompt, isNot(contains('认识 0 天')));
    },
  );
}
