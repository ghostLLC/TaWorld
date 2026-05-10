# TaWorld Flutter 前端开发指南

> **目标读者**: 负责实现具体页面的 AI 模型或开发者
>
> **前提**: 设计系统已建好，你只需要用组件搭建页面。

---

## 一、项目结构

```
app/lib/
├── main.dart                      # 入口
├── app/                           # 应用级配置
│   ├── app.dart                   # MaterialApp 根组件
│   ├── router.dart                # GoRouter 路由表
│   ├── theme.dart                 # 主题配置（亮色+暗色）
│   ├── design_tokens.dart         # 设计令牌（颜色/间距/圆角/阴影）
│   └── typography.dart            # 字体配置
├── core/                          # 核心工具
│   ├── constants/
│   │   └── api_endpoints.dart     # API 路径常量
│   └── network/
│       ├── dio_client.dart        # Dio HTTP 客户端
│       └── api_response.dart      # 统一响应模型
├── services/
│   └── auth_service.dart          # Token 管理
└── presentation/
    ├── screens/                   # 页面
    │   ├── login/login_screen.dart    # ★ 参考实现
    │   └── home/home_screen.dart      # ★ 参考实现
    └── widgets/                   # 组件库
        ├── widgets.dart           # 统一导出
        ├── ta_card.dart
        ├── ta_button.dart
        ├── ta_text_field.dart
        ├── ta_avatar.dart
        ├── ta_loading.dart
        ├── ta_notification_card.dart
        └── ta_achievement_badge.dart
```

---

## 二、新建页面的标准流程

### 步骤 1: 创建页面文件

```dart
// lib/presentation/screens/achievements/achievements_screen.dart

import 'package:flutter/material.dart';
import '../../../app/design_tokens.dart';
import '../../widgets/widgets.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

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

在 `lib/app/router.dart` 中替换对应的 `_Placeholder`：

```dart
GoRoute(
  path: Routes.achievements,
  builder: (_, __) => const AchievementsScreen(),  // 替换 _Placeholder
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
  text: '登录',
  icon: Icons.login_rounded,   // 可选图标
  loading: isLoading,          // 加载态
  onPressed: () {},
)
```

### TaTextField — 输入框

```dart
TaTextField(
  label: '手机号',
  hint: '请输入手机号',
  prefixIcon: Icons.phone_rounded,
  obscureText: false,          // 密码模式
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

### TaNotificationCard — 提醒卡片

```dart
TaNotificationCard(
  type: ReminderCardType.weather,
  message: 'Ta那边要下雨了 🌂',
  time: '2小时前',
  confirmed: false,
  onConfirm: () {},
)
```

### TaAchievementBadge — 成就徽章

```dart
TaAchievementBadge(
  icon: '🌂',
  name: '初次守护',
  progress: 1,
  target: 1,
  unlocked: true,
  points: 10,
)
```

### TaLoading / TaEmptyState / TaErrorState

```dart
// 加载中
TaLoading(message: '加载中...')

// 空状态
TaEmptyState(
  icon: Icons.people_outline_rounded,
  title: '还没有关系',
  subtitle: '邀请你关心的人加入吧',
  actionText: '创建邀请',
  onAction: () {},
)

// 错误状态
TaErrorState(
  message: '网络连接失败',
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

## 五、API 调用规范

### 创建 Dio 实例

```dart
import 'package:taworld/core/network/dio_client.dart';
import 'package:taworld/core/constants/api_endpoints.dart';

final dio = createDioClient();
```

### 发起请求

```dart
// GET
final resp = await dio.get(ApiEndpoints.me);

// POST
final resp = await dio.post(ApiEndpoints.login, data: {
  'phone': '13800001234',
  'password': '123456',
});

// 解析响应
if (resp.data['code'] == 0) {
  final data = resp.data['data'];
  // 成功处理
} else {
  final message = resp.data['message'];
  // 错误处理
}
```

### 错误处理

```dart
try {
  final resp = await dio.post(ApiEndpoints.login, data: {...});
  // ...
} on DioException catch (e) {
  if (e.response != null) {
    // 服务端返回了错误（如 400/401/404）
    final msg = e.response?.data?['message'] ?? '请求失败';
  } else {
    // 网络不可达
    const msg = '网络连接失败，请稍后重试';
  }
}
```

---

## 六、页面状态管理模式

每个页面应处理 4 种状态：

```dart
class _SomeScreenState extends State<SomeScreen> {
  bool _loading = true;
  String? _error;
  List<SomeModel> _data = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final dio = createDioClient();
      final resp = await dio.get(ApiEndpoints.someEndpoint);
      if (resp.data['code'] == 0) {
        setState(() {
          _data = (resp.data['data'] as List).map(...).toList();
          _loading = false;
        });
      } else {
        setState(() { _error = resp.data['message']; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = '加载失败'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const TaLoading(message: '加载中...');
    if (_error != null) return TaErrorState(message: _error!, onRetry: _loadData);
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

## 八、待实现页面清单

| 页面 | 路由 | 复杂度 | 关键组件 |
|------|------|--------|---------|
| 注册页 | `/register` | 低 | TaTextField × 2 + TaButton |
| 关系管理页 | `/relationships` (tab内) | 中 | TaCard 列表 + TaAvatar |
| 关系详情页 | `/relationships/:id` | 中 | TaCard + 提醒配置入口 |
| 提醒配置页 | `/reminders/config/:relId` | 中 | 表单 + Switch + TimePicker |
| 提醒历史页 | `/reminders/:id/logs` | 低 | TaNotificationCard 列表 |
| 成就列表页 | `/achievements` | 中 | TaAchievementBadge 网格 |
| AI 对话页 | `/ai/chat` | 中 | 聊天气泡 + 输入框 |
| 个人中心页 | `/profile` (tab内) | 低 | TaAvatar + 菜单列表 |
| 设置页 | `/settings` | 低 | Switch + ListTile |

> **参考 `login_screen.dart` 和 `home_screen.dart` 了解完整的页面实现模式。**
