# Care Graph and Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已确认的关心图谱、人物天气信息、“聊聊 Ta”主动作和统一快捷栏落到 TaWorld Flutter 应用，并用温柔、通透但不过度装饰的视觉层次替代同权卡片堆叠。

**Architecture:** 保留 `HomeScreen` 的三页 `PageView` 和现有本地预加载／后台天气刷新逻辑；新增独立的 `CareGraphView` 负责径向图谱及选中人物详情，`HomeScreen` 只负责列表／图谱切换和跨页导航。新增轻量草稿通知通道，让图谱的“聊聊 Ta”切回小念页并把建议语放入输入框，不自动发送。

**Tech Stack:** Flutter 3.41.9、Material 3、现有 StatefulWidget/setState、timezone、flutter_animate、flutter_test

**Spec:** Ardot `TaWorld → 06｜体验优化提案 → 06B-02 / 06B-03 / 06D-01 / 06D-02 / 06D-03 / 06D-05 / 06D-06`

## Global Constraints

- 不修改或回退当前工作区中与提醒、时区、备份和对话反馈有关的未提交成果。
- 所有颜色、间距、圆角、时长从 `design_tokens.dart` 或 `ThemeData.colorScheme` 推导，不在页面散落品牌色常量。
- 本地人物数据必须立即显示；天气继续后台刷新，不能恢复全屏等待。
- 图谱总览必须直接显示人物城市、当地时间、天气描述和温度；缺失数据要显示诚实的降级文案。
- “聊聊 Ta”是选中人物详情中的唯一主按钮；提醒和档案是次级动作。
- 快捷项统一为“文字在左、透明 Material 图标在右”，触控区域不小于 48dp。
- 支持浅色／深色主题、文字缩放、SafeArea、长昵称和无天气状态。

---

### Task 1: 定稿 Ardot 三处修订

**Files:**
- Modify: Ardot `06B-02｜关心图谱·总览`
- Modify: Ardot `06B-03｜关心图谱·选中人物`
- Modify: Ardot `06D-02｜小念首页重做`

**Interfaces:**
- Produces: Flutter 实现使用的节点信息层级、主次动作和快捷项顺序。

- [x] **Step 1:** 总览节点附近增加城市／当地时间和天气／温度两行弱化文字。
- [x] **Step 2:** 选中人物增加天气摘要，将“聊聊 Ta”提升为珊瑚色主按钮。
- [x] **Step 3:** 将“写句晚安”调整为文字在左、图标在右。
- [x] **Step 4:** 截图并检查三张稿的裁切、重叠与信息层级。

### Task 2: 用测试锁定图谱信息和主动作

**Files:**
- Create: `app/lib/presentation/screens/home/care_graph_view.dart`
- Create: `app/test/presentation/care_graph_view_test.dart`

**Interfaces:**
- Produces: `CareGraphView(partners, weatherByPartner, weatherLoadingIds, configsByPartner, onChatPartner, onAddReminder, onOpenProfile)`
- Produces: `CareGraphPartnerMeta.localTime(Partner, DateTime)` 和 `CareGraphPartnerMeta.weatherLabel(...)`

- [x] **Step 1: Write the failing tests**

```dart
testWidgets('overview exposes city local time weather and temperature', (tester) async {
  await tester.pumpWidget(graphWith(
    partner: singaporePartner,
    weather: const WeatherResult(text: '多云', temp: 29),
  ));
  expect(find.textContaining('新加坡'), findsOneWidget);
  expect(find.textContaining('多云 · 29°C'), findsOneWidget);
});

testWidgets('selected partner exposes one prominent chat action', (tester) async {
  await tester.pumpWidget(graphWith(partner: singaporePartner));
  await tester.tap(find.text('小乐'));
  await tester.pumpAndSettle();
  expect(find.widgetWithText(FilledButton, '聊聊 Ta'), findsOneWidget);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `C:/flutter/bin/flutter test test/presentation/care_graph_view_test.dart`

Expected: FAIL because `CareGraphView` does not exist.

- [x] **Step 3: Implement the graph**

```dart
class CareGraphView extends StatefulWidget {
  const CareGraphView({
    super.key,
    required this.partners,
    required this.weatherByPartner,
    required this.weatherLoadingIds,
    required this.configsByPartner,
    required this.onChatPartner,
    required this.onAddReminder,
    required this.onOpenProfile,
  });
}
```

Use a responsive `LayoutBuilder + Stack + CustomPainter`: stable partner-ID angles, equal node sizes and equal line weights, a central “我” node, and subdued metadata below each partner node. Selected state enlarges only the chosen node and reveals a semantic detail surface with a full-width `FilledButton.icon(label: Text('聊聊 Ta'))`.

- [x] **Step 4: Run the focused test**

Run: `C:/flutter/bin/flutter test test/presentation/care_graph_view_test.dart`

Expected: PASS.

### Task 3: Integrate list/graph switching and chat handoff

**Files:**
- Modify: `app/lib/presentation/screens/home/home_screen.dart`
- Modify: `app/lib/presentation/screens/ai_home/ai_home_screen.dart`
- Modify: `app/test/presentation/home_screen_retention_test.dart`

**Interfaces:**
- Produces: `AiHomeScreen({ValueNotifier<String?>? draftNotifier})`
- Consumes: `CareGraphView` from Task 2.

- [x] **Step 1: Write failing integration tests**

```dart
await tester.tap(find.text('图谱'));
expect(find.byType(CareGraphView), findsOneWidget);
await tester.tap(find.text('小乐'));
await tester.tap(find.text('聊聊 Ta'));
expect(find.text('小念'), findsWidgets);
```

Also switch away and back, then assert the graph selection and local partner data remain visible without `加载中...`.

- [x] **Step 2: Verify RED**

Run: `C:/flutter/bin/flutter test test/presentation/home_screen_retention_test.dart`

Expected: FAIL because the graph toggle and chat handoff are not integrated.

- [x] **Step 3: Implement integration**

Add a compact list／graph segmented control above the content. Keep `_PartnersTab` alive, pass existing weather/config maps to `CareGraphView`, and route chat through:

```dart
void _openPartnerChat(Partner partner) {
  _aiDraft.value = '我想聊聊${partner.nickname}，帮我看看最近可以怎么关心 Ta';
  _pageController.animateToPage(0, duration: TaAnimation.normal, curve: TaAnimation.curve);
}
```

`AiHomeScreen` listens for a non-empty draft, fills the composer, focuses the keyboard, and clears the notifier without sending.

- [x] **Step 4: Verify GREEN**

Run: `C:/flutter/bin/flutter test test/presentation/home_screen_retention_test.dart`

Expected: PASS.

### Task 4: Replace the inconsistent quick chips

**Files:**
- Create: `app/lib/presentation/screens/ai_home/ai_quick_action_chip.dart`
- Modify: `app/lib/presentation/screens/ai_home/ai_home_screen.dart`
- Create: `app/test/presentation/ai_quick_action_chip_test.dart`

**Interfaces:**
- Produces: `AiQuickActionChip(label, icon, iconColor, onPressed)`.

- [x] **Step 1: Write the failing test**

```dart
expect(tester.getTopLeft(find.text('写句晚安语')).dx,
       lessThan(tester.getTopLeft(find.byIcon(Icons.bedtime_rounded)).dx));
```

- [x] **Step 2: Verify RED**

Run: `C:/flutter/bin/flutter test test/presentation/ai_quick_action_chip_test.dart`

Expected: FAIL because `AiQuickActionChip` does not exist.

- [x] **Step 3: Implement the chip**

Use `Semantics + Material + InkWell + Row(mainAxisSize: min)`, with label first and icon second. The pill uses a softly tinted theme surface, a low-alpha outline, no image asset, and a 48dp minimum height.

- [x] **Step 4: Verify GREEN**

Run: `C:/flutter/bin/flutter test test/presentation/ai_quick_action_chip_test.dart`

Expected: PASS.

### Task 5: Apply restrained visual polish

**Files:**
- Modify: `app/lib/presentation/screens/home/care_graph_view.dart`
- Modify: `app/lib/presentation/screens/home/home_screen.dart`
- Modify: `app/lib/presentation/screens/ai_home/ai_home_screen.dart`
- Modify: `app/lib/presentation/widgets/ta_card.dart` only if a shared surface defect is confirmed.

**Interfaces:**
- Consumes: existing `ColorScheme`, `TaSpacing`, `TaRadius`, `TaAnimation`.

- [x] **Step 1:** Replace equal-weight card stacking with one graph focal surface, flat supporting rows, and one highlighted selected-person surface.
- [x] **Step 2:** Use primary coral for the main chat action, secondary gold for reminder/status information, and tertiary blue for weather/information states.
- [x] **Step 3:** Keep typography mostly regular/semibold; reserve bold for page title, person name and primary action.
- [x] **Step 4:** Add only low-opacity shadows and borders that improve separation in both themes; do not add decorative glass blur or unrelated gradients.
- [x] **Step 5:** Respect reduced motion by limiting selection animation to the existing theme duration and avoiding looping scale/pulse effects.

### Task 6: Full verification and knowledge sync

**Files:**
- Modify: necessary test files
- External: TaWorld Feishu knowledge base development timeline and relevant design/development memo

- [x] **Step 1:** Run `C:/flutter/bin/dart format lib test`.
- [x] **Step 2:** Run focused graph, home retention, quick chip and conversation tests.
- [x] **Step 3:** Run `C:/flutter/bin/flutter analyze --no-pub`.
- [x] **Step 4:** Run `C:/flutter/bin/flutter test`.
- [x] **Step 5:** Run `C:/flutter/bin/flutter build apk --debug` or the project-approved release build when environment time allows.
- [x] **Step 6:** Compare implementation at 390×844 against the corrected Ardot hierarchy and fix material differences.
- [x] **Step 7:** Add one concise chronological Feishu entry: problem, decision, implementation, verification, remaining risk; update the design memo only with stable rules.
