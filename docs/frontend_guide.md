# TaWorld 当前前端开发指南

> 适用于 `app/lib/`。业务边界和架构分别见根 `AGENTS.md` 与 `architecture.md`。

## 1. 页面与导航

首页是三栏 `PageView`：小念、关心的人、我的。需要保活的 Tab 使用 `AutomaticKeepAliveClientMixin`，并在 `build` 中调用 `super.build(context)`。

主要路由：

| 页面 | 路径 |
| --- | --- |
| 首次引导 | `/onboarding` |
| 首页 | `/` |
| 添加人物 | `/partners/add` |
| 人物详情 | `/partners/:id` |
| 提醒配置 | `/reminders/config/:partnerId` |
| 提醒历史 | `/reminders/:id/logs` |
| 成就 | `/achievements` |
| 提醒检查 | `/settings/reminder-health` |
| 设置与子页面 | `/settings`、`/settings/notifications`、`/settings/appearance`、`/settings/ai-data`、`/settings/account` |
| 已移出的人 | `/settings/archived-people` |
| API Key | `/settings/api-keys` |

`/ai/chat` 是保留的旧独立对话入口；主产品流程使用首页小念，新增功能不要绕开主对话工作流。

## 2. 状态与异步数据

保持 `StatefulWidget + setState`，不引入新的状态管理框架或 repository 层。页面应分别处理加载、错误、空数据和正常数据，不能用空列表掩盖读取失败。

```dart
Future<void> _loadAll() async {
  setState(() => _loading = true);
  try {
    final items = await SomeLocalService.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _error = null;
      _loading = false;
    });
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _error = '读取失败，请重试';
      _loading = false;
    });
  }
}
```

异步任务需要考虑 `mounted`、重复请求、旧请求覆盖新结果和部分数据可用的情况。可选服务可以独立降级，但不能用空 `catch` 隐藏失败。

## 3. 主题与设计令牌

颜色、间距、圆角、阴影和尺寸优先使用：

- `Theme.of(context).colorScheme`；
- `TaSpacing`、`TaRadius`、`TaSizes`、`TaGradients`；
- 需要 success/warning/info 等扩展语义色时，使用 `taColorsFor(brightness)`。

五套浅色主题的 primary、secondary、tertiary 前景对比度必须至少为 4.5:1。不要在组件中写死 `TaLightColors`、`Colors.white` 或另一套亮度的颜色。

当前关键令牌：

- 普通卡片内边距 16px，大卡片 24px。
- 标准圆角 16px，大型对话框/弹层 24px。
- 通用图标按钮默认至少 48×48px。
- 暗色模式优先边框，不使用浅色阴影。

修改主题后至少检查当前 palette、暗色模式和其他 palette，不能只检查默认珊瑚色。

## 4. 组件与布局

通用组件位于 `app/lib/presentation/widgets/`：

- `TaCard`：默认、渐变、描边卡片。
- `TaButton` / `TaIconButton`：主操作与图标操作，包含加载/禁用状态。
- `TaTextField`：统一输入，密钥字段设置 `obscureText: true`。
- `TaAvatar`：本地头像与占位符。
- `TaLoading` / `TaEmptyState` / `TaErrorState`：加载、空和错误状态。
- `TaAchievementBadge`：成就进度与新解锁展示。

布局约定：

- 使用 `Expanded`、`Wrap`、`OverflowBar` 和受控滚动处理不同宽度与字体。
- 小念健康卡只在异常或证据未知时出现，正常状态不占首屏。
- 次要操作进入有 tooltip/语义的菜单，不把破坏性操作藏在长按中。
- 提醒配置的内容与开关为第一层，编辑/历史为第二层，摘要最多两行。
- 大字体或窄屏不能只靠一行省略号隐藏关键操作和状态。

## 5. 动效与可访问性

列表动画使用有上限的 stagger：

```dart
final card = buildCard();
if (TaAnimation.reduceMotion(context)) return card;
return card.animate().fadeIn(
  delay: TaAnimation.stagger(index, stepMilliseconds: 80),
  duration: TaAnimation.normal,
);
```

`TaAnimation.stagger` 默认最多延迟 300ms。此次修改过的加载、思考、庆祝、列表和按钮反馈需要静态降级，不得让控制器在减少动态效果时继续无意义播放。

成就只在后续新解锁时庆祝，首次加载已有成就只建立基线。不能把进入页面或下拉刷新当成新解锁。

可访问性检查包括：

- 原生按钮/链接、可见文本和语义标签；
- 至少 48px 的常用触控目标；
- 不只依赖颜色表达成功/失败；
- `MediaQuery.disableAnimations`；
- 390px、深色和 200% 字体场景。

## 6. 人物、时间和状态文案

人物列表与图谱统一调用 `CareGraphPartnerMeta.localTime`，不得另写经度估算。时区未知时显示待确认，不显示误导性的具体时间。

提醒历史与检查必须区分已安排、已提交、通知栏检测到、用户确认和无法确认。不要把“发送成功”写成对方已读或实际联系成功。

## 7. 新增或修改页面

1. 先确认业务状态和数据来源，再设计页面层级。
2. 使用现有路由、服务、设计令牌和通用组件。
3. 处理加载、错误、空数据、长文本、深色和大字体。
4. 为行为变化先写能失败的测试，再实现。
5. 运行 `tool/taworld.ps1 analyze --no-pub` 和完整 `test --no-pub`。
6. 涉及发布时再通过三 ABI 构建，不把构建成功当作真机视觉验收。

品牌角色和现有图片资产当前暂缓调整；不要为了局部页面美化擅自替换吉祥物或重新生成整套素材。
