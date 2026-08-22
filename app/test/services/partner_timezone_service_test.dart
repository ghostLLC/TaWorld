import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/services/local/partner_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

  test('partner service creates and updates IANA timezone metadata', () async {
    final created = await PartnerService.add(
      nickname: '小乐',
      type: 'friend',
      timezoneId: 'Asia/Singapore',
      timezoneSource: 'city_lookup',
      timezoneConfirmed: false,
    );

    expect(created.timezoneId, 'Asia/Singapore');
    expect(created.timezoneConfirmed, isFalse);

    await PartnerService.update(
      created.id,
      timezoneId: 'Asia/Singapore',
      timezoneSource: 'user_confirmed',
      timezoneConfirmed: true,
    );
    final updated = await PartnerService.getById(created.id);

    expect(updated?.timezoneSource, 'user_confirmed');
    expect(updated?.timezoneConfirmed, isTrue);
  });

  test(
    'changing city without a replacement timezone invalidates old metadata',
    () async {
      final created = await PartnerService.add(
        nickname: '小乐',
        type: 'friend',
        city: 'Singapore',
        timezoneId: 'Asia/Singapore',
        timezoneSource: 'user_confirmed',
        timezoneConfirmed: true,
      );

      await PartnerService.update(created.id, city: 'Los Angeles');
      final updated = await PartnerService.getById(created.id);

      expect(updated?.city, 'Los Angeles');
      expect(updated?.timezoneId, isNull);
      expect(updated?.timezoneSource, isNull);
      expect(updated?.timezoneConfirmed, isFalse);
    },
  );

  test('failed creation can hard-delete its provisional partner row', () async {
    final created = await PartnerService.add(nickname: '临时人物', type: 'friend');

    await PartnerService.deleteCreated(created.id);

    expect(await PartnerService.getById(created.id), isNull);
  });

  test('failed update can restore the exact partner snapshot', () async {
    final original = await PartnerService.add(
      nickname: '小乐',
      type: 'partner',
      note: '原始备注',
      city: 'Singapore',
      timezoneId: 'Asia/Singapore',
      timezoneSource: 'user_confirmed',
      timezoneConfirmed: true,
    );

    await PartnerService.update(
      original.id,
      nickname: '错误名字',
      type: 'friend',
      note: '错误备注',
      city: 'Los Angeles',
      timezoneId: 'America/Los_Angeles',
      timezoneSource: 'user_confirmed',
      timezoneConfirmed: true,
    );
    await PartnerService.restoreSnapshot(original);

    final restored = await PartnerService.getById(original.id);
    expect(restored?.toMap(), original.toMap());
  });
}
