import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/presentation/screens/partner_detail/partner_detail_screen.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await openTestDatabase();
    await (await DatabaseHelper.database).insert('partners', {
      'id': 'partner-1',
      'nickname': '小乐',
      'type': 'family',
      'status': 'active',
      'created_at': '2026-10-01T00:00:00.000Z',
      'updated_at': '2026-10-01T00:00:00.000Z',
    });
  });

  tearDown(closeTestDatabase);

  testWidgets(
    'partner statistics describe record age rather than relationship age',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PartnerDetailScreen(partnerId: 'partner-1')),
      );

      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('已记录天数').evaluate().isNotEmpty) break;
      }

      expect(find.text('已记录天数'), findsOneWidget);
      expect(find.text('陪伴天数'), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
