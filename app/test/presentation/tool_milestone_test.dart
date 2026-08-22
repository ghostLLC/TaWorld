import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/presentation/screens/ai_home/milestone_message_card.dart';
import 'package:taworld/presentation/screens/ai_home/tool_execution_result.dart';

void main() {
  test('verified state change serializes a success contract for the model', () {
    final result = ToolExecutionResult.success(
      toolName: 'create_reminder',
      modelMessage: '已为小乐创建天气提醒',
      title: '天气提醒已设置',
      detail: '小乐 · 每天 08:00',
      entityId: 'reminder-1',
      verified: true,
    );

    final payload = jsonDecode(result.toModelContent()) as Map<String, dynamic>;
    expect(payload, {
      'tool': 'create_reminder',
      'status': 'success',
      'verified': true,
      'message': '已为小乐创建天气提醒',
      'entity_id': 'reminder-1',
    });
    expect(result.milestone?.status, ToolExecutionStatus.success);
    expect(result.milestone?.title, '天气提醒已设置');
  });

  test('saved but unscheduled reminder is reported as partial success', () {
    final result = ToolExecutionResult.partialSuccess(
      toolName: 'create_reminder',
      modelMessage: '提醒已保存，但系统通知尚未调度成功',
      title: '提醒已保存',
      detail: '请检查通知权限后重试',
      entityId: 'reminder-2',
      verified: true,
    );

    final payload = jsonDecode(result.toModelContent()) as Map<String, dynamic>;
    expect(payload['status'], 'partial_success');
    expect(payload['verified'], isTrue);
    expect(result.milestone?.status, ToolExecutionStatus.partialSuccess);
  });

  test('read-only tool result does not create a milestone', () {
    final result = ToolExecutionResult.information(
      toolName: 'get_partner_weather',
      modelMessage: '广州 28°C 晴',
    );

    expect(result.milestone, isNull);
    expect(
      (jsonDecode(result.toModelContent()) as Map<String, dynamic>)['status'],
      'information',
    );
  });

  test('milestone metadata round-trips through local history', () {
    const milestone = ToolMilestone(
      status: ToolExecutionStatus.success,
      title: '已添加关心的人',
      detail: '小乐 · 伴侣',
    );

    expect(ToolMilestone.fromMap(milestone.toMap()).toMap(), milestone.toMap());
  });

  testWidgets(
    'milestone card makes a successful operation independently visible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const milestone = ToolMilestone(
        status: ToolExecutionStatus.success,
        title: '天气提醒已设置',
        detail: '小乐 · 每天 08:00',
      );

      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneMessageCard(
              milestone: milestone,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('天气提醒已设置'), findsOneWidget);
      expect(find.text('小乐 · 每天 08:00'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byTooltip('收起结果'), findsOneWidget);
      expect(_semanticsLabel('操作成功'), findsOneWidget);
      await tester.tap(find.byTooltip('收起结果'));
      expect(dismissed, isTrue);
      semantics.dispose();
    },
  );

  testWidgets('partial and failed operations are never painted as success', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const partial = ToolMilestone(
      status: ToolExecutionStatus.partialSuccess,
      title: '提醒已保存',
      detail: '系统通知尚未调度成功',
    );
    const failure = ToolMilestone(
      status: ToolExecutionStatus.failure,
      title: '提醒未创建',
      detail: '没有找到小乐',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MilestoneMessageCard(milestone: partial),
              MilestoneMessageCard(milestone: failure),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(_semanticsLabel('部分完成'), findsOneWidget);
    expect(_semanticsLabel('操作失败'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    semantics.dispose();
  });
}

Finder _semanticsLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}
