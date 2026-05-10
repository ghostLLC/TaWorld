# TaWorld 前端设计系统规范

> **适用范围**: Flutter 移动端（`app/` 目录）
>
> **代码位置**: 所有设计令牌定义在 `lib/app/design_tokens.dart`

---

## 一、色板

### 亮色模式

| 用途 | 色值 | 变量名 | 示例 |
|------|------|--------|------|
| 主色（AppBar/主按钮） | `#E8998D` 柔珊瑚 | `TaLightColors.primary` | 🟧 |
| 主色上文字 | `#FFFFFF` | `TaLightColors.onPrimary` | ⬜ |
| 次要色（成就/徽章） | `#D4A855` 暖金 | `TaLightColors.secondary` | 🟨 |
| 第三色（天气模块） | `#7EB8CC` 天空蓝 | `TaLightColors.tertiary` | 🔵 |
| 全局背景 | `#FFF8F5` 暖奶油白 | `TaLightColors.background` | ⬜ |
| 卡片表面 | `#FFFFFF` | `TaLightColors.surface` | ⬜ |
| 输入框/次要卡片 | `#FFF0EB` 淡桃 | `TaLightColors.surfaceVariant` | 🟠 |
| 正文文字 | `#2C1810` 深暖棕 | `TaLightColors.onSurface` | 🟤 |
| 次要文字 | `#6B5147` | `TaLightColors.onSurfaceVariant` | 🟫 |
| 边框/分割线 | `#E0C9C2` | `TaLightColors.outline` | 🔲 |
| 错误 | `#D32F2F` | `TaLightColors.error` | 🔴 |
| 成功 | `#66BB6A` | `TaLightColors.success` | 🟢 |

### 暗色模式（温暖暗色，非冷灰）

| 用途 | 色值 | 变量名 |
|------|------|--------|
| 主色 | `#FFB4A2` 亮桃粉 | `TaDarkColors.primary` |
| 全局背景 | `#1A1210` 温暖炭棕 | `TaDarkColors.background` |
| 卡片表面 | `#2A2220` 暖深棕 | `TaDarkColors.surface` |
| 输入框 | `#3A312E` 暖灰棕 | `TaDarkColors.surfaceVariant` |
| 正文文字 | `#F5E6DF` 暖白 | `TaDarkColors.onSurface` |

**关键原则**: 暗色模式使用暖色调暗棕色（非冷灰黑），营造"温暖的晚上"而非"冰冷的夜晚"。

---

## 二、间距系统（8px 基线网格）

| 令牌 | 值 | 用途 |
|------|----|------|
| `TaSpacing.xxs` | 4px | 最小间距（图标与文字） |
| `TaSpacing.xs` | 8px | 紧凑间距 |
| `TaSpacing.sm` | 12px | 元素内间距 |
| `TaSpacing.md` | 16px | **标准间距**（最常用） |
| `TaSpacing.lg` | 24px | 段落/分组间距 |
| `TaSpacing.xl` | 32px | 区域间距 |
| `TaSpacing.xxl` | 48px | 大段分隔 |
| `TaSpacing.pagePadding` | 20px | **页面水平边距** |

### 常用 EdgeInsets

```dart
TaSpacing.page          // 水平 20px 的页面边距
TaSpacing.cardInner     // 16px 的卡片内边距
TaSpacing.cardInnerLarge // 24px 的大卡片内边距
```

---

## 三、圆角系统

| 令牌 | 值 | 用途 |
|------|----|------|
| `TaRadius.xs` | 8px | 小标签/Chip |
| `TaRadius.sm` | 12px | 小按钮/SnackBar |
| `TaRadius.md` | 16px | **标准圆角（卡片/按钮/输入框）** |
| `TaRadius.lg` | 24px | 对话框/BottomSheet |
| `TaRadius.full` | 999px | 胶囊形/头像 |

**规则**: 所有卡片和按钮使用 `TaRadius.md`（16px），不允许使用其他圆角值。

---

## 四、阴影系统

使用暖色调阴影（`Color(0x1A5C4033)` 而非纯黑），营造柔和感。

| 令牌 | 模糊半径 | 偏移 | 用途 |
|------|---------|------|------|
| `TaShadows.sm` | 8px | (0, 2) | 卡片默认阴影 |
| `TaShadows.md` | 16px | (0, 4) | 悬浮元素 |
| `TaShadows.lg` | 24px | (0, 8) | 模态弹窗 |

**注意**: 暗色模式下不使用阴影（使用边框替代）。

---

## 五、字体

- **西文**: Nunito（Google Fonts，圆润友好）
- **中文**: 系统默认（Android: Noto Sans CJK, iOS: PingFang SC）
- **配置文件**: `lib/app/typography.dart`

| 样式 | 字号 | 字重 | 用途 |
|------|------|------|------|
| `displayLarge` | 32px | Bold | 启动页标题 |
| `displayMedium` | 28px | Bold | 页面大标题 |
| `headlineMedium` | 20px | SemiBold | 区域标题 |
| `titleLarge` | 18px | Bold | 卡片标题 |
| `titleMedium` | 16px | SemiBold | 子标题 |
| `bodyLarge` | 16px | Regular | **正文（最常用）** |
| `bodyMedium` | 14px | Regular | 次要正文 |
| `bodySmall` | 12px | Regular | 辅助文字 |
| `labelLarge` | 14px | SemiBold | 按钮文字 |
| `labelSmall` | 11px | Medium | 标签/角标 |

---

## 六、渐变

| 令牌 | 颜色 | 用途 |
|------|------|------|
| `TaGradients.primary` | 珊瑚→深珊瑚 | 主按钮、AppBar 装饰 |
| `TaGradients.warm` | 桃粉→暖金 | 概览卡片背景 |
| `TaGradients.gold` | 暖金→深金 | 成就解锁 |
| `TaGradients.sky` | 浅蓝→天空蓝 | 天气模块 |

---

## 七、动画

| 令牌 | 值 | 用途 |
|------|----|------|
| `TaAnimation.fast` | 200ms | 微交互（按下反馈） |
| `TaAnimation.normal` | 300ms | **标准过渡** |
| `TaAnimation.slow` | 500ms | 复杂动画 |
| `TaAnimation.curve` | easeInOutCubic | **标准缓动** |
| `TaAnimation.bounce` | elasticOut | 弹性效果（Logo 出场） |

---

## 八、组件库速查

所有组件在 `lib/presentation/widgets/` 中，通过 `widgets.dart` 统一导出。

| 组件 | 文件 | 说明 |
|------|------|------|
| `TaCard` | `ta_card.dart` | 卡片（默认/渐变/描边） |
| `TaButton` | `ta_button.dart` | 渐变主按钮（含加载态+按下动画） |
| `TaIconButton` | `ta_button.dart` | 小号圆形图标按钮 |
| `TaTextField` | `ta_text_field.dart` | 输入框（含密码切换） |
| `TaAvatar` | `ta_avatar.dart` | 头像（sm/md/lg/xl 四种尺寸） |
| `TaLoading` | `ta_loading.dart` | 加载动画（跳动心形 ❤️） |
| `TaEmptyState` | `ta_loading.dart` | 空状态（图标+文案+可选按钮） |
| `TaErrorState` | `ta_loading.dart` | 错误状态 |
| `TaNotificationCard` | `ta_notification_card.dart` | 提醒通知卡片（含类型图标/确认按钮） |
| `TaAchievementBadge` | `ta_achievement_badge.dart` | 成就徽章（进度环+解锁标记） |

---

## 九、设计原则

1. **温暖感** — 使用暖色调，避免冷蓝/冷灰
2. **圆润感** — 大圆角（16px），圆润字体
3. **呼吸感** — 充足的间距，不拥挤
4. **一致性** — 所有颜色/间距/圆角从设计令牌取值，禁止硬编码
5. **响应性** — 微动画让界面有生命力（入场淡入、按下缩放）
