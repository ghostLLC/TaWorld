# TaWorld 官网 · 维护交接指南

> 本文档写给下一位维护者（人或 AI）。请**完整阅读"硬性规则"与"来龙去脉"**再动手——这个网站的设计决策全部来自用户 (ghostLLC) 的逐轮反馈，理解它们才能保持一致性。
>
> 最后更新：2026-08-23 · 当前版本 v6 · 线上版本 CloudBase `taworld-009`

---

## 一、这是什么

TaWorld 是一款 Flutter Android 应用（本地优先的 AI 关怀助手，详见仓库根 `README.md`）。本目录 (`website/`) 是它的产品官网：

- **单文件纯静态站**：全部内容在 `index.html`（内联 CSS + JS，零构建步骤）
- **零外部依赖**：不引用任何 CDN、网络字体、第三方脚本——这是中国大陆秒开的前提，**不可破坏**
- **双部署**：
  - 主站（大陆直连）：`https://taworld-cloud1-8grf0qgi8c6c0603.webapps.tcloudbase.com`（腾讯云 CloudBase 静态托管，上海）
  - 镜像：`https://ghostllc.github.io/TaWorld/`（GitHub Pages，gh-pages 分支）
- 页面本体约 116KB，全部图片约 150KB + OG 图 1.1MB

## 二、来龙去脉（版本史与用户偏好演进）

理解这条演进线非常重要——**用户的审美是一轮轮校准出来的**：

| 版本 | 用户反馈 | 产出 |
|---|---|---|
| v1 | 初版需求：为 GitHub 项目写产品官网，大陆可访问 | 浅色珊瑚主题单页，功能分区 |
| v2 | "更高级、有设计感、更丰富交互；**不能用 emoji**；避免语句生硬" | 手绘 SVG 线性图标系统（约 25 个 symbol）、杂志式章节编号、Bento 网格、手机三屏轮播、打字机对话演示、可点通知闭环、主题切换预览、文案全面重写 |
| v3 | "首屏夜色电影感很好；**LOGO 不是 APP 的 LOGO**；星座图信息卡被爱心重叠；再高级些，现在太普通太素" | ① 发现 `app/web/icons/Icon-512.png` 是**旧版蓝色图标**，改用 `app/android/.../mipmap-xxxhdpi/ic_launcher.png`（真身，暖珊瑚）；② 深色电影感首屏（星空/月亮/金边手机）+ 金色强调；③ 信息卡智能避让（上半区节点弹下方、下半区弹上方） |
| v4 | "中间背景也用这种风格；**聊天气泡长短不一**是 bug；**星座图的爱心直接去掉**；继续升级" | ① 全站夜色化（"温暖的晚上"，取自应用暗色模式 #1C110D 系）；② 插画无透明通道 → 放入奶油色**画框托板** `.plate`；③ 气泡统一宽度 `min(430px,100%)`；④ 星座图节点改金色几何图形（圆环/房子/星/菱形），信息卡标题用菱形符标；⑤ 手机 3D 倾斜、Bento 聚光灯、标题逐字浮现 |
| v5 | "**标题、色彩、背景同质化了**；想办法更电影感、高级感" | **电影分幕调色（color script）**：八幕各有主色（见下表）；场记板胶囊「第X幕·汉字」；镜头暗角；动态胶片颗粒；标题 clip-path 幕布揭示 + 主色辉光；记忆/图谱两幕居中大标题；图谱幕重排为通栏标题 |
| v6 | "结尾那句还是旧效果，换掉；**思考还有哪些角度没做到**" | 结尾打字机（与首屏同引擎 `typeCycle`，落日色系）；右侧**章节选单轨**（八菱形，当前幕发光，悬停显汉字）；**提灯夜行**（暖光随光标，screen 混合）；幽灵大字滚动视差；按钮涟漪；通知卡呼吸脉动（首点即停，行为演示产品哲学）；页脚巨型描线签名 |
| 补丁 | "图、诺、启、问四幕没有巨型汉字" | 八幕幽灵汉字补全：念护忆图醒诺启问 |

**用户画像总结**：对视觉品质要求很高且逐轮迭代；喜欢"电影感/夜色/金色/温暖"的方向；讨厌 emoji、模板腔文案、元素重叠错位、长短不齐这类"不精致"的细节；乐于接受新交互但要求克制统一。

## 三、硬性规则（违反任何一条都算事故）

1. **全站禁用 emoji**。包括看似无害的符号字符（♥ ⌂ ✦ ☰ 等——有些平台会渲染成彩色 emoji），一律用内联 SVG path。自查命令（Git Bash）：
   ```bash
   perl -CSD -ne 'while (/([\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE0F}\x{2764}])/g) { print "$.: $1\n" }' index.html
   ```
   （JS 注释里的排版箭头 `→` 可接受，不渲染）
2. **网站 LOGO/图标必须来自** `app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`（暖珊瑚色）。**禁止**使用 `app/web/icons/Icon-512.png`——那是旧版蓝色图标，用户亲自抓过这个 bug。再生成命令：
   ```bash
   magick app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png -filter Lanczos -resize 384x384 -quality 90 -define webp:method=6 website/assets/img/icon-512.webp
   ```
3. **零外部依赖**：新增任何 `<link>`/`<script src>`/`@import` 指向外部域都是回归。字体只用系统栈（`--serif`/`--sans` 已定义）。
4. **聊天气泡统一宽度**（用户定为 bug）：`.bubble .msg` 与 `.typing` 均 `width:min(430px,100%)`。
5. **星座图禁用心形**（用户要求移除）：节点用金色几何图形，信息卡标题前是 CSS 菱形（`.g-tip b::before`）。
6. **文案事实以根 `README.md` 为准**，不要采用 `competition/创意提案.md` 里过时/夸大的表述（如"DeepSeek V4 Pro 驱动"“24国300+城市”——实际默认 `deepseek-v4-flash`；城市定位不做具体数字声明）。语气：温暖、克制、有文学性，避免营销模板腔。
7. **`prefers-reduced-motion` 必须全量降级**：所有动画在 reduce 下退化为静态（打字机直接显示全部字符、视差/提灯/脉动不启动）。全局 `@media` 已兜底，新增 JS 动画要检查 `reduced` 变量。
8. **插画 PNG 无透明通道**（白底），在深色卡片上必须包 `.plate` 托板呈现。
9. 中文衬线依赖用户系统字体（Noto Serif SC → 宋体回退），**不要**为了统一字形引入 webfont。
10. APK（56MB）**不进 git**（`website/.gitignore` 排除 `downloads/*.apk`）；CloudBase 部署时随目录上传，gh-pages 用 sed 把下载链接改写为 GitHub Release 附件地址。

## 四、设计系统速查

### 4.1 基础色板（`:root`）

| 令牌 | 值 | 用途 |
|---|---|---|
| `--bg0/--bg1/--bg2` | `#150C09/#1B100B/#221410` | 页面/面板底（暖夜棕） |
| `--card/--card-2/--raise` | `#241610/#2B1C13/#33221A` | 卡片层次 |
| `--text/--mut/--faint` | `#F5E6DF/#C0A296/#8F776B` | 奶油字/次要/微弱 |
| `--coral/--coral-deep` | `#E8998D/#B44A3B` | 主行动色（APP 品牌色） |
| `--gold/--gold-lt` | `#C2913D/#DCB26A` | 金色强调系统 |
| `--line/--line-2` | rgba 奶油 11%/7% | 描边发丝线 |
| `--plate-a/--plate-b` | `#FBF6EF/#F1E4D6` | 插画托板渐变 |

五套主题色（与 APP `design_tokens.dart` 一致，用于主题实验室与打字机配色）：暖珊瑚 `#E8998D`、薰衣草 `#9B8EC4`、海洋蓝 `#5B98C4`、樱花粉 `#E88DAA`、森林绿 `#7EAA88`。

### 4.2 电影分幕调色（核心差异化机制）

每幕一个场景类，设 `--acc`（主色）与 `--acc-soft`（顶部辉光），章节编号描边/eyebrow/act-tag/图标底色/卡片悬停边/幽灵汉字/标题辉光全部自动取 `--acc`：

| 幕 | id | 场景类 | acc | 排版变体 |
|---|---|---|---|---|
| 第一幕 · 念 | `#who` | （默认） | 珊瑚 `#E8998D` | 左对齐，ghost 右 |
| 第二幕 · 护 | `#features` | `.sc-gold` | 金 `#DCB26A` | 左对齐，ghost 左 |
| 第三幕 · 忆 | `#memory` | `.sc-lav` | 薰衣草 `#B7A8E3`，整节偏紫底 | **居中** `.head-center` |
| 第四幕 · 图 | `#graph` | `.sc-blue` | 蓝 `#8FBFDD`，整节偏蓝底 | **居中**，通栏标题 |
| 第五幕 · 醒 | `#reminders` | `.sc-sakura` | 樱粉 `#E990AC` | 左对齐（内含第六幕·礼，普通左对齐头） |
| 第七幕 · 诺 | `#privacy` | `.sc-void` | 暗金 `#C2913D`，近黑 | 面板内 |
| 第八幕 · 启 | `#download` | `.sc-ember` | 余烬 `#DE8070` | ghost 左 |
| 问答 | `#faq` | （默认） | 珊瑚 | 居中头，ghost 右 |

加新章节：拷贝一个 `<section class="section sc-xxx">` + `<span class="ghost">汉字</span>` + chapter-head 结构（act-tag + eyebrow + h2），并把它加进 JS 的 `railDefs`（章节选单轨）。

### 4.3 幽灵汉字

八枚巨型衬线字（`.ghost` 280px，`color-mix(var(--acc) 7%)`），直接子级于 section，`ghost-l` 换左侧，参与滚动视差（JS `ghosts` 段）。**新增章节必须补 ghost**——用户专门提过遗漏。

### 4.4 组件清单

- **Bento 功能网格** `.bento`：6 列，主卡 `.b-hero`（span4），聚光灯 `.spot`（JS pointermove 写 `--mx/--my`）
- **对话演示** `#chatDemo`：JS 逐条打字（typing 圆点 1s → 气泡浮现），「再看一遍」重播；进入视口触发一次
- **星座图** `#graphWrap`：夜空画布（星星/双层旋转虚线轨道/流动连线 `.g-line` march 动画）；节点 `.g-node` 悬停/点击出信息卡 `.g-tip`，**点击钉住、点空白收起**，定位有智能避让（上半区节点 → 卡在下方）
- **通知闭环演示** `#notifDemo`：三按钮状态机（ok/later/skip → 不同反馈文案），呼吸脉动 `.pulsing` 首点移除
- **主题实验室** `#themeRow`：点色丸实时改 `#themePreview` 的 `--tp/--tp-deep` 与背景
- **统计带** `.stats`：`data-count` 数字滚动（30/5/7/169）
- **章节选单轨** `#actRail`：右缘固定，8 菱形 + 汉字，IO 同步当前幕，≤1180px 隐藏
- **提灯** `#lantern`：全视口固定层，`backgroundPosition` 随光标 lerp（仅 pointer:fine）
- **打字机引擎** `typeCycle(el, palette, D, HOLD, DEL, PAUSE)`：首屏（`#heroTitle`）与结尾（`#finaleTitle`，进入视口后启动）共用；逐字异色 + 金色光标 + 打字/停/删/重来循环
- **跑马灯**、**进度条**、**scrollspy**、**回顶**、**按钮涟漪**、**手机三屏轮播 + 3D 倾斜 + 滚动视差**、**幕布标题揭示**（`.chapter-head.reveal h2` 的 clip-path，注意只作用于带 `.reveal` 的头）
- **胶片颗粒** `body::after`（steps 跳动）+ **镜头暗角** `.vignette`

### 4.5 图片资产（`assets/img/`）

全部由 `app/assets/images/` 与启动图标经 ImageMagick 压缩而来（`-resize` + webp q82 method6）。需要替换插画时按同样规格重新生成，保持页面轻量。OG 分享图 `og-banner.png`（1200×630）生成命令（Windows 有微软雅黑可用了再跑）：

```bash
magick -size 1200x630 gradient:'#FFF8F5'-'#FFE0DA' \
  \( app/assets/images/onboarding_mascot.png -resize 460x460 \) -gravity east -geometry +70+10 -composite \
  -font C:/Windows/Fonts/msyhbd.ttc -pointsize 96 -fill '#5C2018' -gravity northwest -annotate +80+120 'TaWorld' \
  -pointsize 60 -fill '#C75B4C' -annotate +84+240 '把牵挂变成恰到好处的行动' \
  -font C:/Windows/Fonts/msyh.ttc -pointsize 34 -fill '#6B5248' -annotate +86+340 '本地优先 AI 关怀助手 · 数据只保存在你的手机里' \
  -pointsize 28 -fill '#9A7E71' -annotate +86+430 'github.com/ghostLLC/TaWorld' \
  website/assets/img/og-banner.png
```

注意：og-banner 是**旧浅色版**产物，与现站夜色风格不完全一致——若要重做，改成夜底金字即可（mascot + 渐变字），1200×630 不变。

## 五、部署与更新流程

### 5.1 三端同步（每次改动后）

```bash
# ① master（源码入库）
cd D:/TaWorld && git add website/ && git commit -m "..." && git push origin master

# ② gh-pages（worktree + 链接改写）
git worktree add ../TaWorld-ghpages gh-pages
cd D:/TaWorld-ghpages
cp D:/TaWorld/website/index.html .
sed -i 's|href="downloads/TaWorld-v0.1.1-arm64-v8a.apk"|href="https://github.com/ghostLLC/TaWorld/releases/download/v0.1.1/TaWorld-v0.1.1-arm64-v8a.apk"|g' index.html
git add -A && git commit -m "publish: ..." && git push origin gh-pages
cd D:/TaWorld && git worktree remove ../TaWorld-ghpages --force

# ③ CloudBase（MCP 工具 cloudbase）
manageApps(action="deployApp", serviceName="taworld", framework="static",
           filePath="D:\\TaWorld\\website", buildPath=".", installCmd="", buildCmd="",
           ignore=["**/node_modules/**","**/.git/**","**/README.md"])
# 然后用 queryApps(action="getAppVersion", buildId=<返回值>) 轮询到 SUCCESS（约 30-40s）
```

CloudBase 环境已绑定：`cloud1-8grf0qgi8c6c0603`（用户账号，MCP `cloudbase` 已登录）。若登录过期，让用户执行 `auth(action="start_auth")` 扫码。

- gh-pages 的 sed 目标串随版本号变化，注意同步更新
- GitHub Pages 构建后 CDN 边缘缓存可能滞后几分钟，验证时带 `?v=n` 参数绕过
- CloudBase 的 APK 走相对路径 `downloads/...`（部署目录内 `website/downloads/` 下的 APK 一起上传）

### 5.2 发新版本 checklist

1. 新 APK 复制为 `website/downloads/TaWorld-vX.Y.Z-arm64-v8a.apk`（gitignore 已排除，不会入库）
2. `index.html` 中搜索 `v0.1.1`，更新版本号/日期/体积/更新日志（changelog details 块）
3. `gh release create vX.Y.Z "website/downloads/TaWorld-vX.Y.Z-arm64-v8a.apk" --title ... --notes ...`（gh 已登录 ghostLLC）
4. sed 改写串换为新 Release 地址；三端同步（5.1）
5. 根 `README.md` 的官网/下载链接行同步更新

## 六、测试清单（每次改版必做）

本地预览：`cd website && python -m http.server 8123`，浏览器开 `http://localhost:8123`。

1. **emoji 扫描**（见硬性规则 1 的 perl 命令，应零输出）
2. **桌面 1440px**：无横向溢出、全部图片加载（`img.complete && naturalWidth>0`）、reveal 全触发、八个 ghost 在位
3. **移动 390px**：无横向滚动（`window.scrollTo(80,0)` 后 `scrollX===0`）、菜单开关、章轨隐藏
4. **交互点**：轮播自动切换、对话打字+重播、通知三态、主题切换、图谱信息卡（悬停+点击钉住+点空白收起，且不与节点圆相交）、打字机两处循环、涟漪、脉动首点消失
5. **⚠️ IO 伪影**：headless/程序化快速滚动时 IntersectionObserver 会因帧节流"漏触发"大量 reveal——**这不是 bug**。验证 reveal 用"逐元素位置停留 1s"的方式（本次交接前刚排查过，勿重蹈覆辙）。另外 `scroll-behavior:smooth` 会让测试里的 `scrollTo` 变动画，测滚动用 `behavior:'instant'`
6. **Mimosa commit 钩子**：本仓库 commit 前会全仓库安全扫描，发现 high 项（如硬编码凭据）会**强制拦截且 `--no-verify` 无效**（工具层钩子）。`server/tests/` 的历史哑密码已修复（随机生成），现在 commit 一般能过；若提示 `python_ast_unavailable ... 按兼容策略继续` 属正常放行，不代表审计通过。新拦截需真修复，勿绕过

## 七、已知边界与待办池

- **og-banner 仍为浅色旧版**（见 4.5），可重做为夜色版
- **CloudBase 默认域名**免备案可用；绑定自定义域名需 ICP + `manageGateway bindCustomDomain`
- APK 为开发签名（页面 FAQ/下载区已如实说明）；正式分发前应换正式签名并更新文案
- `color-mix()`、`:focus-visible`、`steps()` 等现代 CSS 依赖（2026 主流浏览器均 OK；若要兼容旧浏览器需评估替换）
- LICENSE：根 README 徽章写 MIT 但仓库无 LICENSE 文件，页面措辞已避开许可证声明
- 手机内演示屏是 APP 浅色模式（在夜色页面上刻意形成对比），不要"顺手统一"
- 页脚 `foot-mark`、跑马灯、marquee 双语标签等装饰元素均 `aria-hidden`，改动时保持

## 八、快速改动手册

| 需求 | 做法 |
|---|---|
| 改文案 | 全部在 `index.html` 内直接搜中文；章节标题在 `chapter-head` 的 `<h2>` |
| 加/改一幕 | 见 4.2 末尾；记得同步 `railDefs` 与 ghost |
| 调某幕氛围色 | 改对应 `sc-*` 类的 `--acc/--acc-soft`；薰衣草/蓝两幕还有整节底色渐变 |
| 打字机换文案/配色 | 改 `heroPal`/`finPal` 数组与 `#heroTitle`/`#finaleTitle` 内文本（引擎自动逐字拆分，`<br>` 保留） |
| 换主题实验室主题 | `#themeRow` 按钮 `data-p/data-d/data-bg` + APP `design_tokens.dart` 保持一致 |
| 图片更新 | 从 `app/assets/images/` 重新压缩生成（保持 webp 与现有命名） |

## 九、给 AI 维护者的操作纪律

- 本仓库 master 直接推送（无 PR 流程），但**只 push 与网站/明确任务相关的提交**；不要顺手提交根目录的 APK 大文件或无关改动
- 对外发布（CloudBase/gh-pages）是不可逆的线上动作，改动上线前先本地全量跑第六节清单
- 用户反馈风格强烈（见第二节），拿不准"够不够高级"时，倾向：更克制、更统一、更有叙事性，而不是加更多元素
- 一切以根 `README.md` 的事实为准；与 APP 代码不一致的宣传口径宁可少说
