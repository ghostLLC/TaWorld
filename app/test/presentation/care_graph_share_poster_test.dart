import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:taworld/data/models/partner.dart';
import 'package:taworld/presentation/screens/home/care_graph_share_poster.dart';

void main() {
  testWidgets('share poster carries brand context and a project QR code', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 22);
    final partner = Partner(
      id: 'partner-1',
      nickname: '小乐',
      type: 'partner',
      city: '广州',
      status: 'active',
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CareGraphSharePoster(partners: [partner], reminderCount: 2),
        ),
      ),
    );

    expect(find.text('我的关心图谱'), findsOneWidget);
    expect(find.text('看见彼此，也记得每一份牵挂'), findsOneWidget);
    expect(find.textContaining('TaWorld'), findsWidgets);
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
