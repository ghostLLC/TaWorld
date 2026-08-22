import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/services/local/partner_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

  test('all partner mutations publish a refresh event', () async {
    final initial = PartnerService.refreshCounter.value;
    final partner = await PartnerService.add(
      nickname: '小乐',
      type: 'partner',
    );
    expect(PartnerService.refreshCounter.value, initial + 1);

    await PartnerService.update(partner.id, city: '广州');
    expect(PartnerService.refreshCounter.value, initial + 2);

    await PartnerService.dissolve(partner.id);
    expect(PartnerService.refreshCounter.value, initial + 3);
  });
}
