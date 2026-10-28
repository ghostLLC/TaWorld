## TaWorld 视觉素材升级方案

> 全项目扫描结果：当前共使用 **38 种不同 Emoji**，分布在 **107 处**。以下按优先级分组，给出每个素材的位置、风格要求、尺寸和 AI 生成提示词。

**统一风格关键词**（所有素材共用）：
warm, soft, friendly, flat illustration, pastel coral and gold palette, rounded shapes, no text, clean white or transparent background, suitable for a care/relationship mobile app

---

### 规范角色定义（跨场景一致性）

所有包含同一语义主体的图片，**必须**使用以下规范描述来保证角色外观一致。生成提示词中须完整嵌入对应角色的规范描述。

#### AI 机器人吉祥物（TaBot）

用于：AI 配置页插画、AI 空聊天状态、未来可能出现的 AI 相关页面。

> A cute kawaii-style robot mascot with: a large round white dome-shaped head, a small golden ball antenna on top of the head, a dark charcoal-gray rounded rectangular face panel on the front with two large round warm-amber glowing eyes and a simple curved smile line, two small pink-coral circular blush marks on the white cheeks outside the face panel, a compact chubby white body, a small golden circular emblem button at the center of the chest, short stubby white arms with small round hands, short legs with small rounded feet.

核心特征清单：
- 头部：白色圆顶，顶部金色球天线
- 面部：深炭灰色面板，琥珀色大圆眼 × 2，弧线微笑
- 脸颊：面板外的白色区域各有粉色腮红
- 胸口：金色圆形徽章
- 四肢：白色短粗手臂 + 圆手，短腿 + 圆脚
- 配色：白/奶油色主体，金色点缀，珊瑚色腮红

#### 小狐狸吉祥物（FoxMascot）

用于：引导页主视觉。仅出现一次，无需跨图一致。

---

### Phase 1 — 品牌标识级（用户第一印象，最高优先级）

#### 1.1 引导页主视觉（App Mascot）

| 项 | 内容 |
|---|---|
| **位置** | `onboarding_screen.dart` — 引导页第一步，120×120 渐变圆圈内的 ❤️ 图标 |
| **当前** | Material Icons 的 `Icons.favorite_rounded`，放在暖色渐变圆里 |
| **替换为** | App 吉祥物/品牌插画 — 一个温暖的小角色（小狐狸/小熊/抽象生物）双手捧着爱心 |
| **尺寸** | 360×360px PNG（显示为 120dp），透明背景 |
| **提示词** | A cute, friendly mascot character (small round fox with rosy cheeks) gently holding a glowing heart in both paws, flat illustration style, warm coral (#E8998D) and gold (#D4A855) color palette, soft pastel tones, simple rounded shapes, transparent background, no text, kawaii-inspired, suitable for a care and relationship app icon |

#### 1.2 引导页 AI 配置步骤插画

| 项 | 内容 |
|---|---|
| **位置** | `onboarding_screen.dart` — 引导页第二步「配置 AI 服务」，目前无插画 |
| **当前** | 纯表单，没有视觉焦点 |
| **替换为** | 一个友好的 AI 小机器人角色，手持钥匙或对话气泡，表情温暖 |
| **尺寸** | 360×300px PNG，透明背景 |
| **提示词** | A friendly, approachable small robot character holding a golden key, with a warm smile and soft glowing eyes, flat illustration style, warm coral and cream color palette, rounded cute design, simple shapes, transparent background, no text, kawaii-inspired, suitable for a care app AI assistant persona |

#### 1.3 AI 聊天空状态插画

| 项 | 内容 |
|---|---|
| **位置** | `ai_home_screen.dart` — AI 主屏无消息时的中心插画，当前是 72×72 渐变方块 + 🤖 图标 |
| **当前** | `Icons.smart_toy_rounded` 放在渐变圆角方块里 |
| **替换为** | AI 吉祥物全身像，周围飘浮着爱心、星星和对话气泡 |
| **尺寸** | 300×300px PNG，透明背景 |
| **提示词** | A cute friendly robot mascot character in a welcoming pose, surrounded by floating small hearts, stars, and chat bubbles, flat illustration style, warm coral (#E8998D) and gold (#D4A855) palette, soft dreamy background elements, simple rounded shapes, transparent background, no text, kawaii-inspired |

---

### Phase 2 — 高频交互级（用户每天看到，高优先级）

#### 2.1 加载动画（替换心跳）

| 项 | 内容 |
|---|---|
| **位置** | `ta_loading.dart` — 全局加载动画，被 6 个页面使用 |
| **当前** | `Icons.favorite_rounded` 做 0.85×~1.15× 缩放循环，800ms |
| **替换为** | Lottie 动画：一颗温暖的爱心有节奏地跳动，周围散发小粒子 |
| **格式** | Lottie JSON（~20KB），64×64dp |
| **动画方案** | 心跳节奏 1.2s 循环：0~30% 放大+发光 → 30~60% 缩小回弹 → 60~100% 静止等待。粒子在放大时向外散发 4~6 个小暖色圆点 |
| **提示词** | A stylized heartbeat animation, a warm coral heart gently pulsing with small golden particles radiating outward, minimal flat design, soft glow effect, warm coral (#E8998D) and gold (#D4A855), transparent background, looping animation, suitable for mobile app loading state |

#### 2.2 AI 思考指示器

| 项 | 内容 |
|---|---|
| **位置** | `ai_home_screen.dart` — 发送消息后「AI 正在思考...」旁边的 16×16 转圈 |
| **当前** | `CircularProgressIndicator`，非常通用 |
| **替换为** | 三个暖色圆点依次跳动，或 AI 小角色的思考动画（可用 Lottie 或纯 Flutter 动画） |
| **格式** | 纯 Flutter 实现即可（3 个 Container 做延迟弹跳），或 Lottie JSON |
| **动画方案** | 3 个圆点（珊瑚色），间距 6px，依次做 Y 轴弹跳（delay 0/150/300ms），600ms 循环 |

#### 2.3 快捷芯片图标（5 个）

| # | 当前 Emoji | 位置 | 替换为 | 尺寸 | 提示词 |
|---|-----------|------|--------|------|--------|
| 1 | ☀️ 今日天气 | AI 主屏底部芯片 | 扁平太阳插画 | 20×20dp | A simple flat sun icon with soft rays, warm gold (#D4A855) color, minimal design, white background, no text |
| 2 | 🌙 写句晚安语 | AI 主屏底部芯片（晚间） | 扁平月亮插画 | 20×20dp | A simple flat crescent moon icon with a small star, soft navy and gold colors, minimal design, white background, no text |
| 3 | 🌞 写句早安语 | AI 主屏底部芯片（白天） | 扁平日出插画 | 20×20dp | A simple flat sunrise icon with a small sun rising over a gentle horizon line, warm coral and gold colors, minimal design, white background, no text |
| 4 | 💝 关心建议 | AI 主屏底部芯片 | 扁平爱心灯泡 | 20×20dp | A simple flat icon combining a heart shape with a lightbulb, warm coral (#E8998D) color, minimal design, white background, no text |
| 5 | 🍚 提醒吃饭 | AI 主屏底部芯片 | 扁平饭碗插画 | 20×20dp | A simple flat icon of a cute rice bowl with chopsticks and a small steam wisp, warm coral and cream colors, minimal design, white background, no text |

#### 2.4 关系类型选择卡片（3 个）

| # | 当前 Emoji | 位置 | 替换为 | 尺寸 | 提示词 |
|---|-----------|------|--------|------|--------|
| 1 | ❤️ 情侣 | `add_partner_screen.dart` + `partner_detail_screen.dart` 类型选择 | 情侣插画 | 84×84px PNG | Two cute simple characters holding hands under a small floating heart, flat illustration, warm coral palette, rounded shapes, transparent background, no text, kawaii style |
| 2 | 🏠 家人 | 同上 | 家庭插画 | 84×84px PNG | A cute small family (parent and child) standing in front of a cozy house with a heart-shaped door, flat illustration, warm coral and gold palette, rounded shapes, transparent background, no text, kawaii style |
| 3 | 🤝 朋友 | 同上 | 朋友插画 | 84×84px PNG | Two cute simple characters sharing a gift or waving at each other cheerfully, flat illustration, warm coral palette, rounded shapes, transparent background, no text, kawaii style |

---

### Phase 3 — 空状态插画（提升品质感，中优先级）

#### 3.1 关心的人列表空状态

| 项 | 内容 |
|---|---|
| **位置** | `home_screen.dart` _PartnersTab — 「还没有关心的人」空状态 |
| **当前** | `Icons.people_outline_rounded` 在 TaEmptyState 组件中 |
| **替换为** | 一个人温柔地捧着空白爱心相框的插画 |
| **尺寸** | 400×400px PNG，透明背景（显示 160dp） |
| **提示词** | A warm illustration of a gentle character holding an empty heart-shaped photo frame, with a subtle plus sign inviting to add someone, flat soft style, warm coral (#E8998D) and cream palette, rounded shapes, transparent background, no text, conveys warmth and invitation not loneliness |

#### 3.2 成就列表空状态

| 项 | 内容 |
|---|---|
| **位置** | `achievements_screen.dart` — 「暂无成就」空状态 |
| **替换为** | 一个发光的奖杯，周围有柔和的星星 |
| **提示词** | A cute glowing trophy sitting on a soft cloud or cushion, surrounded by gentle sparkles and small stars, flat illustration, warm gold (#D4A855) and coral palette, transparent background, no text, conveys anticipation and motivation |

#### 3.3 提醒历史空状态

| 项 | 内容 |
|---|---|
| **位置** | `reminder_history_screen.dart` — 「暂无提醒记录」空状态 |
| **替换为** | 一个梦幻的沙漏，里面飘着爱心形状的沙粒 |
| **提示词** | A dreamy hourglass with small heart-shaped sand particles gently floating inside, soft glow around it, flat illustration, warm coral and gold palette, transparent background, no text, conveys time waiting to be filled with care |

#### 3.4 提醒配置空状态

| 项 | 内容 |
|---|---|
| **位置** | `reminder_config_screen.dart` — 「还没有提醒」空状态 |
| **替换为** | 一个温柔的闹钟/通知气泡，里面有爱心 |
| **提示词** | A gentle cute alarm bell with a small heart inside, surrounded by soft radiating lines suggesting a notification, flat illustration, warm coral and gold palette, transparent background, no text, friendly and inviting |

#### 3.5 错误状态

| 项 | 内容 |
|---|---|
| **位置** | `ta_loading.dart` TaErrorState — 全局错误重试状态 |
| **替换为** | 一个可爱但略困惑的小角色，带着创可贴 |
| **提示词** | A cute slightly confused small character with a tiny bandage on its head, looking puzzled but not distressed, flat illustration, warm muted coral palette, transparent background, no text, conveys oops not critical error, friendly and approachable |

---

### Phase 4 — 成就徽章图标（7 个，替换 Emoji）

所有成就徽章统一风格：圆形徽章内的小插画，金色描边，暖色调。

| # | 成就名称 | 当前 Emoji | 替换为插画 | 提示词 |
|---|---------|-----------|-----------|--------|
| 1 | 初次守护 | 🌂 | 爱心盾牌 | A small shield with a heart in the center, flat badge icon style, gold (#D4A855) outline, warm coral fill, transparent background, no text |
| 2 | 连续守护7天 | 🔥 | 七星盾牌 | A small shield with 7 tiny stars arranged in an arc above it, flat badge icon style, gold outline, warm coral fill, transparent background, no text |
| 3 | 晚安大使 | 🌙 | 月亮睡帽 | A crescent moon wearing a cute sleeping cap with a small star, flat badge icon style, gold outline, navy and coral fill, transparent background, no text |
| 4 | 干饭督导 | 🍚 | 可爱饭碗角色 | A cute rice bowl character with chopsticks and a happy face, flat badge icon style, gold outline, warm coral fill, transparent background, no text |
| 5 | 百日陪伴 | 💯 | 金心日历 | A small calendar page with a golden heart in the center, flat badge icon style, gold outline, warm coral fill, transparent background, no text |
| 6 | 创意达人 | 🎨 | 灯泡闪光 | A lightbulb with small sparkle rays around it, flat badge icon style, gold outline, warm coral and gold fill, transparent background, no text |
| 7 | 双向奔赴 | ❤️ | 双心箭头 | Two hearts with small arrows pointing toward each other, flat badge icon style, gold outline, warm coral fill, transparent background, no text |

**尺寸**：每个 112×112px PNG（显示 56dp），透明背景

---

### Phase 5 — 动画增强（锦上添花）

#### 5.1 天气卡片动态头部

| 项 | 内容 |
|---|---|
| **位置** | `ai_home_screen.dart` _WeatherCard — 渐变蓝色背景的天气预警卡片 |
| **当前** | 🌦️ Emoji + 纯文字 |
| **替换为** | 4 套天气场景小插画（横幅格式），根据天气条件切换 |

| 天气 | 提示词 |
|------|--------|
| 下雨 | A cute flat illustration of raindrops falling on a small umbrella with a warm glow underneath, sky blue and coral palette, horizontal banner format, transparent background, no text |
| 下雪 | A cute flat illustration of snowflakes falling around a cozy scarf and mittens, sky blue and white palette, horizontal banner format, transparent background, no text |
| 酷热 | A cute flat illustration of a melting ice cream with a small sun blazing above, warm orange and gold palette, horizontal banner format, transparent background, no text |
| 酷寒 | A cute flat illustration of a small character bundled in layers with visible cold breath, icy blue and warm coral palette, horizontal banner format, transparent background, no text |

**尺寸**：每张 600×160px PNG（显示为卡片全宽 × 60~80dp）

#### 5.2 成就解锁庆祝动画

| 项 | 内容 |
|---|---|
| **位置** | `achievements_screen.dart` — 成就解锁时的视觉反馈 |
| **当前** | 仅颜色变化，无动画 |
| **替换为** | 金色 + 珊瑚色粒子爆炸动画（Lottie） |
| **格式** | Lottie JSON（~30KB），120×120dp 覆盖层 |
| **动画方案** | 解锁瞬间：中心闪光 → 环形粒子向外爆发（金色+珊瑚色小圆点/星星）→ 淡出。总时长 800ms |

#### 5.3 连续天数火焰等级

| 项 | 内容 |
|---|---|
| **位置** | `ai_home_screen.dart` 状态栏 — 🔥 streak 徽章 |
| **当前** | 固定 🔥 Emoji + 数字 |
| **替换为** | 3 级火焰插画，随连续天数变化 |

| 天数 | 插画 | 提示词 |
|------|------|--------|
| 1~3 天 | 小蜡烛 | A tiny cute candle with a small gentle flame, flat icon style, warm gold and coral, transparent background, no text |
| 4~7 天 | 篝火 | A small cozy campfire with warm dancing flames, flat icon style, warm gold and coral, transparent background, no text |
| 8+ 天 | 大火焰 | A bold warm bonfire with energetic flames and small sparks, flat icon style, bright gold and coral, transparent background, no text |

**尺寸**：每个 48×48px PNG（显示 20dp）

---

### Phase 6 — 提醒分类图标（4 个，贯穿全 App）

这 4 个图标在 7+ 个位置重复出现（卡片、配置、统计、通知），替换后收益最高。

| # | 分类 | 当前 Emoji | 替换为 | 尺寸 | 提示词 |
|---|------|-----------|--------|------|--------|
| 1 | 天气提醒 | 🌦️ | 云朵太阳组合 | 48×48 PNG | A simple flat icon of a small sun peeking behind a soft cloud with a few raindrops, warm coral and sky blue palette, minimal design, transparent background, no text |
| 2 | 睡觉提醒 | 🌙 | 月亮星星组合 | 48×48 PNG | A simple flat crescent moon with two small stars beside it, warm navy and gold (#D4A855) palette, minimal design, transparent background, no text |
| 3 | 吃饭提醒 | 🍚 | 饭碗筷子组合 | 48×48 PNG | A simple flat cute rice bowl with chopsticks and a tiny steam wisp, warm coral palette, minimal design, transparent background, no text |
| 4 | 自定义提醒 | 💝 | 爱心信封组合 | 48×48 PNG | A simple flat love letter envelope with a small heart seal, warm coral and gold palette, minimal design, transparent background, no text |

**出现位置**：
- `home_screen.dart` — 展开卡片配置行（20px）、统计分类（18px）
- `reminder_config_screen.dart` — 配置列表项（24px）、类型选择对话框（28px）
- `reminder_scheduler.dart` — 通知标题
- `care_suggestion_service.dart` — 关怀建议文本

---

### 素材总览

| 类别 | 数量 | 格式 | 优先级 |
|------|------|------|--------|
| 品牌插画（引导页+AI吉祥物） | 3 张 | PNG 360px | Phase 1 |
| 加载/思考动画 | 2 个 | Lottie + Flutter 动画 | Phase 2 |
| 快捷芯片图标 | 5 个 | PNG 40px | Phase 2 |
| 关系类型插画 | 3 个 | PNG 84px | Phase 2 |
| 空状态插画 | 5 张 | PNG 400px | Phase 3 |
| 成就徽章插画 | 7 个 | PNG 112px | Phase 4 |
| 天气场景横幅 | 4 张 | PNG 600×160px | Phase 5 |
| 庆祝/火焰动画 | 2 组 | Lottie / PNG 组 | Phase 5 |
| 提醒分类图标 | 4 个 | PNG 48px | Phase 6 |
| **合计** | **~35 张插画 + 4 个动画** | | |

### 实施建议

1. **Phase 1~2 可以立即开始**：品牌插画和高频交互元素对用户感知影响最大
2. **Phase 3~4 批量生成**：空状态和成就徽章风格统一，可以一次性用 AI 批量出图后微调
3. **Phase 5~6 逐步迭代**：动画和细节图标可以在后续版本中逐步加入
4. **Lottie 动画**可以用 AI 工具（如 LottieFiles AI）生成，或先生成静态图后用 Flutter 代码实现简单动画
5. 所有 PNG 素材建议生成后统一用 TinyPNG 压缩，减少包体积
