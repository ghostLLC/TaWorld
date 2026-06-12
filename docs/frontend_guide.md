# TaWorld Flutter 前端开发指南

> **目标读者**: 负责实现具体页面的 AI 模型或开发者
>
> **前提**: 设计系统已建好。TaWorld 是离线优先的独立 Flutter 应用，数据存储在本地 SQLite，不依赖后端服务器。

---

## 一、项目结构

```
app/lib/
├── main.dart
├── app/
│   ├── app.dart              # MaterialApp 根组件
│   ├── router.dart           # GoRouter 路由表（全部已实现）
│   ├── theme.dart            # 主题配置（亮色+暗色）
│   ├── design_tokens.dart    # 设计令牌
│   └── typography.dart       # 字体配置
├── data/
│   ├── models/               # 数据模型
│   │   ├── user.dart         # LocalUser
│   │   ├── partner.dart      # Partner（关心的人）
│   │   ├── reminder_config.dart # ReminderConfig
│   │   ├── reminder_log.dart # ReminderLog
│   │   └── achievement.dart  # Achievement + UserAchievement
│   ├── city_data.dart        # 世界城市数据（24国300+城）
│   └── local/database_helper.dart # SQLite 数据库
├── services/
│   ├── ai_service.dart       # DeepSeek AI
│   ├── weather_service.dart  # wttr.in 天气
│   ├── notification_service.dart # 本地通知
│   ├── reminder_scheduler.dart # 提醒调度
│   ├── background_tasks.dart # WorkManager
│   ├── care_suggestion_service.dart
│   ├── theme_service.dart
│   └── local/                # 本地数据服务
│       ├── local_user_service.dart
│       ├── partner_service.dart
│       ├── local_reminder_service.dart
│       └── local_achievement_service.dart
└── presentation/
    ├── screens/
    │   ├── ai_home/           # AI 主屏（Tab 1）
    │   ├── home/              # 首页 + 关心的人（Tab 2）+ 我的（Tab 3）
    │   ├── add_partner/       # 添加关心的人
    │   ├── partner_detail/    # 关心的人详情/编辑
    │   ├── reminder_config/   # 提醒配置
    │   ├── reminder_history/  # 提醒历史
    │   ├── achievements/      # 成就列表
    │   ├── ai_chat/           # AI 对话（旧版独立页面）
    │   ├── api_key_setup/     # API Key 管理
    │   ├── onboarding/        # 引导页
    │   └── settings/          # 设置
    └── widgets/
        ├── widgets.dart       # 统一导出
        ├── city_picker_sheet.dart # 城市选择器
        ├── ta_card.dart / ta_button.dart / ta_text_field.dart
        ├── ta_avatar.dart / ta_loading.dart
        └── ta_achievement_badge.dart
```

---

## 二、新建页面的标准流程

> **注意**: 当前所有路由均已连接到真实页面，不再需要替换 `_Placeholder`。如需新增页面，按以下流程操作。

### 步骤 1: 创建页面文件

```dart
// lib/presentation/screens/my_feature/my_feature_screen.dart

import 'package:flutter/material.dart';
import '../../../app/design_tokens.dart';
import '../../widgets/widgets.dart';

class MyFeatureScreen extends StatefulWidget {
  const MyFeatureScreen({super.key});

  @override
  State<MyFeatureScreen> createState() => _MyFeatureScreenState();
}

class _MyFeatureScreenState extends State<MyFeatureScreen> {
  bool _loading = true;
  String? _error;
  List<SomeModel> _data = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      // 从本地 SQLite 加载数据（参见第五节）
      final items = await SomeLocalService.getAll();
      setState(() { _data = items; _loading = false; });
    } catch (e) {
      setState(() { _error = '加载失败'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ... 使用 theme 获取颜色和字体
    // ... 使用 TaSpacing / TaRadius 获取间距和圆角
    // ... 使用 TaCard / TaButton 等组件
  }
}
```

### 步骤 2: 注册路由

在 `lib/app/router.dart` 中添加新路由：

```dart
GoRoute(
  path: '/my-feature',
  builder: (_, __) => const MyFeatureScreen(),
),
```

### 步骤 3: 测试

```bash
flutter run -d chrome    # 或连接安卓模拟器
```

---

## 三、组件使用指南

### TaCard — 统一卡片

```dart
// 默认卡片
TaCard(
  child: Text('内容'),
  onTap: () {},              // 可选点击
)

// 渐变头部卡片
TaCard.gradient(
  child: Text('温暖渐变背景'),
)

// 描边卡片
TaCard.outlined(
  child: Text('带边框'),
)
```

### TaButton — 主按钮

```dart
TaButton(
  text: '保存',
  icon: Icons.check_rounded,   // 可选图标
  loading: isLoading,          // 加载态
  onPressed: () {},
)
```

### TaTextField — 输入框

```dart
TaTextField(
  label: '姓名',
  hint: '请输入姓名',
  prefixIcon: Icons.person_rounded,
  obscureText: false,
  controller: _controller,
  validator: (v) => v!.isEmpty ? '必填' : null,
)
```

### TaAvatar — 头像

```dart
TaAvatar(url: user.avatarUrl, name: user.nickname)
TaAvatar.small(url: url)
TaAvatar.large(name: '张三')
TaAvatar.xl(url: url, showBorder: true)
```

### TaAchievementBadge — 成就徽章

```dart
TaAchievementBadge(
  icon: '🌂',
  name: '初次守护',
  progress: 1,
  target: 1,
  unlocked: true,
  // 已解锁时自动显示"已解锁"标签，无需传入 points
)
```

### CityPickerSheet — 城市选择器

```dart
import '../../widgets/city_picker_sheet.dart';

// 弹出城市选择底部弹窗
final selection = await showCityPicker(context);
if (selection != null) {
  // selection.city, selection.province, selection.country
  // selection.displayText — "广东 · 深圳" or "日本 · 东京"
  setState(() { _selectedCity = selection; });
}
```

### TaLoading / TaEmptyState / TaErrorState

```dart
// 加载中
TaLoading(message: '加载中...')

// 空状态
TaEmptyState(
  icon: Icons.people_outline_rounded,
  title: '还没有关心的人',
  subtitle: '添加你关心的人，开始守护吧',
  actionText: '添加',
  onAction: () {},
)

// 错误状态
TaErrorState(
  message: '加载失败',
  onRetry: () {},
)
```

---

## 四、样式规范

### ❌ 禁止做的事

```dart
// ❌ 硬编码颜色
color: Color(0xFFE8998D)

// ❌ 硬编码间距
padding: EdgeInsets.all(16)

// ❌ 硬编码圆角
borderRadius: BorderRadius.circular(16)
```

### ✅ 正确做法

```dart
// ✅ 从主题获取颜色
color: Theme.of(context).colorScheme.primary

// ✅ 使用设计令牌
padding: EdgeInsets.all(TaSpacing.md)

// ✅ 使用圆角常量
borderRadius: TaRadius.borderMd
```

### 常用设计令牌

| 令牌 | 值 | 用途 |
|------|-----|------|
| `TaSpacing.xs` | 8px | 元素内最小间距 |
| `TaSpacing.sm` | 12px | 紧凑间距 |
| `TaSpacing.md` | 16px | 标准间距 |
| `TaSpacing.lg` | 24px | 大间距 |
| `TaSpacing.pagePadding` | 20px | 页面水平边距 |
| `TaRadius.sm` | 12px | 小组件圆角 |
| `TaRadius.md` | 16px | 标准圆角（卡片/按钮） |
| `TaRadius.lg` | 24px | 大圆角（对话框） |

---

## 五、本地服务调用规范

> **架构说明**: TaWorld 是离线优先的独立应用，数据存储在本地 SQLite 数据库中，不依赖后端服务器。外部服务（AI、天气）通过 HTTP 直接调用。

### 本地数据操作（SQLite）

```dart
import '../../../services/local/partner_service.dart';

// 查询全部
final partners = await PartnerService.getAll();

// 按 ID 查询
final partner = await PartnerService.getById(id);

// 创建
final newPartner = await PartnerService.create(partner);

// 更新
await PartnerService.update(partner);
```

其他本地服务用法相同：

```dart
import '../../../services/local/local_user_service.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/local/local_achievement_service.dart';

// 用户
final user = await LocalUserService.getCurrentUser();

// 提醒配置
final reminders = await LocalReminderService.getByPartnerId(partnerId);

// 成就
final achievements = await LocalAchievementService.getAll();
```

### AI 服务

```dart
import '../../../services/ai_service.dart';

// 检查是否已配置 API Key
final hasKey = await AiService.hasApiKey();

// 发送聊天消息
final reply = await AiService.chat(message);
```

### 天气服务

```dart
import '../../../services/weather_service.dart';

// 按城市名获取当前天气
final weather = await WeatherService.getCurrentWeatherByCity('深圳');
```

### 提醒调度

```dart
import '../../../services/reminder_scheduler.dart';

// 重新调度所有已启用的提醒（添加/修改/删除提醒后调用）
await ReminderScheduler.scheduleAll();
```

### 错误处理

```dart
try {
  final partners = await PartnerService.getAll();
  // ...
} catch (e) {
  // SQLite 异常或文件损坏（极少发生）
  setState(() { _error = '读取本地数据失败'; });
}
```

---

## 六、页面状态管理模式

> **说明**: 页面使用 `StatefulWidget` + `setState` 管理状态，不使用 Riverpod 或其他状态管理框架。数据来自本地 SQLite 服务，无网络错误（DioException 等），仅需处理 SQLite 异常。

每个页面应处理 3 种状态：加载中、错误、正常数据：

```dart
class _SomeScreenState extends State<SomeScreen> {
  bool _loading = true;
  String? _error;
  List<SomeModel> _data = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      // 从本地 SQLite 服务加载数据
      final items = await SomeLocalService.getAll();
      setState(() { _data = items; _loading = false; });
    } catch (e) {
      setState(() { _error = '加载失败'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const TaLoading(message: '加载中...');
    if (_error != null) return TaErrorState(message: _error!, onRetry: _loadAll);
    if (_data.isEmpty) return const TaEmptyState(icon: ..., title: '暂无数据');

    // 正常数据展示
    return ListView.builder(...);
  }
}
```

---

## 七、动画规范

```dart
import 'package:flutter_animate/flutter_animate.dart';

// 入场动画
Widget(...).animate()
  .fadeIn(duration: TaAnimation.normal)
  .slideY(begin: 0.05, curve: TaAnimation.curve);

// 延迟入场（列表项依次出现）
Widget(...).animate()
  .fadeIn(delay: (index * 100).ms);

// 标准动画时长
TaAnimation.fast    // 200ms
TaAnimation.normal  // 300ms
TaAnimation.slow    // 500ms
```

---

## 八、页面清单（全部已实现）

| 页面 | 路由 | 文件 | 状态 |
|------|------|------|------|
| 引导页 | `/onboarding` | onboarding_screen.dart | ✅ |
| AI 主屏 | Tab 1 | ai_home_screen.dart | ✅ |
| 关心的人 | Tab 2 | home_screen.dart (_PartnersTab) | ✅ |
| 我的 | Tab 3 | home_screen.dart (_ProfileTab) | ✅ |
| 添加关心的人 | `/partners/add` | add_partner_screen.dart | ✅ |
| 关心的人详情 | `/partners/:id` | partner_detail_screen.dart | ✅ |
| 提醒配置 | `/reminders/config/:partnerId` | reminder_config_screen.dart | ✅ |
| 提醒历史 | `/reminders/:id/logs` | reminder_history_screen.dart | ✅ |
| 成就列表 | `/achievements` | achievements_screen.dart | ✅ |
| AI 对话 | `/ai/chat` | ai_chat_screen.dart | ✅ |
| API Key 管理 | `/settings/api-keys` | api_key_setup_screen.dart | ✅ |
| 设置 | `/settings` | settings_screen.dart | ✅ |

> **所有页面均已实现，路由表完整，无占位符。**
