# TaWorld 产品官网 · 维护交接指南

> 写给下一位维护者（人或 AI）。读完这一份，你应当能独立完成：改版、发版、三端部署、故障排查，并且不破坏既有设计语言与用户已确认的偏好。
> 最后更新：2026-08-23 · 对应线上版本 `taworld-009` · 仓库 `github.com/ghostLLC/TaWorld`

---

## 一、这是什么

TaWorld 是一款**本地优先的 AI 关怀助手** Android 应用（Flutter，v0.1.1）——「把牵挂，变成恰到好处的行动」。本目录（`website/`）是它的产品官网：**单文件纯静态页**，全部逻辑内联在 `index.html`（约 116KB），零外部依赖、零构建步骤。

### 线上地址（双部署）

| 端 | 地址 | 角色 |
|---|---|---|
| **主站** | https://taworld-cloud1-8grf0qgi8c6c0603.webapps.tcloudbase.com | 腾讯云 CloudBase 上海，大陆直连秒开（实测 0.3s），**APK 托管在此站** |
| 镜像 | https://ghostllc.github.io/TaWorld/ | GitHub Pages，海外访问用，下载按钮指向 GitHub Release |

### 硬约束（任何时候都不能破）

1. **零外部依赖**：不引用 Google Fonts、不用任何第三方 CDN/JS 库。这是"大陆轻松打开"的前提。字体走本地系统栈，图标全是内联 SVG。
2. **全站禁止 emoji**：用户明确要求过两次。连 `♥`、`★` 这类可能被系统渲染成 emoji 的字符也不用（星座图节点用纯 SVG path 画的心/房子/星形——但注意：**节点图标里的心形后来也被用户要求去掉了**，见 §5 第四章）。提交前用 §9 的 perl 命令扫描。
3. **单文件**：CSS/JS 全部内联在 `index.html`，不拆文件。图片放 `assets/img/`（全部本地 WebP，整站不含 APK 约 1.4MB）。
4. **文案语气**：温暖、松弛、有文学感，避免模板腔和营销腔。历史打磨过的例句是标杆：「日历里躺着一条『给妈打电话』，像任务清单，不像牵挂」「总说改天再联系，改天却一直没有来」「牵挂不必轰烈，恰到好处，就很好。」

---

## 二、来龙去脉：v1 → v6 的全部决策记录

用户（产品作者）的每次反馈都塑造了现状。**新改动不要逆着这些决策走。**

| 版本 | 用户反馈 | 做了什么 |
|---|---|---|
| v1 | 初版需求："高级、有设计感、丰富的交互；不能用 emoji；避免语句生硬" | 浅色暖珊瑚单页（品牌色取自应用 `design_tokens.dart` 的 `#E8998D`），emoji 全部换成手绘 SVG 线性图标，杂志式章节编号，文案全面重写 |
| v2 | "主图标 LOGO 不是 APP 的 LOGO；星座图信息卡被爱心重叠；再高级些，太普通太素" | ① 发现网站误用了 `app/web/icons/Icon-512.png`（**旧版蓝色图标**），改用真启动图标 `app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`（暖珊瑚）重新生成 `assets/img/icon-512.webp`；② 信息卡智能避让；③ 首屏改深色电影感 |
| v3 | "首屏夜色电影感很好，中间背景也可以尝试这种风格" | 「夜与昼」：深色首屏 + 浅色中段 |
| v4 | "中间标题/色彩/背景同质化了" + "聊天气泡长短不一（bug）" + "信息卡还是被爱心覆盖，直接去掉爱心" | **全站夜色化**（「温暖的晚上」，取自应用暗色模式的品牌叙事）；气泡统一宽度；星座图心形节点与卡片图标全部移除；浅色插画装入奶油色"画框托板" |
| v5 | "更电影感、高级感" | **电影分幕调色（color script）**：八幕各有主色；场记板标签；镜头暗角；动态胶片颗粒；标题幕布式揭示 + 辉光；居中大标题幕（记忆/图谱）打破同质化 |
| v6 | "『恰到好处，就很好。』还是那种点击拖动才出现的字的效果，换掉" + "加入更多丰富效果" | 结尾标题换成与首屏同款**异色打字机循环**（用户此前点名喜欢的效果）；新增：右侧章节选单轨、"提灯夜行"光标暖光、幽灵大字滚动视差、按钮涟漪、通知卡呼吸脉动、页脚巨型签名；补齐八幕巨型汉字 |

### 用户审美偏好速写（判断新点子时的北极星）

- 喜欢：夜色、电影感、金色/暖光、打字机循环动画、"同一台打字机写页首页尾"这类叙事呼应、克制的丰富（效果多但不吵）
- 讨厌：emoji、生硬文案、浅色平淡、各章节长得一样、"需要交互才出现"的静态文字效果（对 scroll-reveal 淡入尤为敏感——重要标题直接用打字机，普通内容 reveal 可以但不要让用户觉得"字是坏的"）

---

## 三、部署架构与更新流程

### 3.1 CloudBase（主站）

- 环境：`cloud1-8grf0qgi8c6c0603`（上海，BaaS）；应用服务名：`taworld`
- 当前已通过设备码授权绑定（若过期，让用户运行 cloudbase MCP `auth start_auth` 重新扫码）
- 部署（cloudbase MCP 工具，**注意 ignore 里排除本文件，避免文档被部署成网页**）：

```
manageApps(action="deployApp", serviceName="taworld", framework="static",
  installCmd="", buildCmd="", buildPath=".", filePath=<website 绝对路径>,
  ignore=["**/node_modules/**","**/.git/**","**/README.md","**/HANDOFF.md"])
```

- 部署后用 `queryApps(action="getAppVersion", buildId=<返回的id>)` 轮询到 SUCCESS（约 30-40s）
- **必须使用返回的 accessUrl，不要自行拼接域名**
- APK 就放在 `website/downloads/`（已 gitignore，只存在于 CloudBase 上），路径 `/downloads/TaWorld-v0.1.1-arm64-v8a.apk`

### 3.2 GitHub Pages（镜像）

- 仓库 `gh-pages` 分支（孤儿内容分支，只有 `index.html` + `assets/` + `robots.txt`）
- **关键差异**：镜像上的两个 APK 下载按钮被 sed 改写指向 GitHub Release：
  `https://github.com/ghostLLC/TaWorld/releases/download/v0.1.1/TaWorld-v0.1.1-arm64-v8a.apk`
- Pages 有 CDN 边缘缓存，推送后旧内容可能残留几分钟；验证新内容用 `curl -s "https://ghostllc.github.io/TaWorld/?v=N"` 绕缓存

### 3.3 标准更新三连（改了 index.html 之后）

```bash
# ① master
git add website/ && git commit -m "feat(website): ..." && git push origin master

# ② gh-pages（worktree 方式；注意分支已存在，不能再用 --orphan）
git worktree add ../TaWorld-ghpages gh-pages
cd ../TaWorld-ghpages
cp D:/TaWorld/website/index.html .
sed -i 's|href="downloads/TaWorld-v0.1.1-arm64-v8a.apk"|href="https://github.com/ghostLLC/TaWorld/releases/download/v0.1.1/TaWorld-v0.1.1-arm64-v8a.apk"|g' index.html
grep -c "releases/download" index.html   # 必须输出 2
git add -A && git commit -m "publish: ..." && git push origin gh-pages
cd D:/TaWorld && git worktree remove ../TaWorld-ghpages --force

# ③ CloudBase：按 3.1 调用 deployApp 并轮询 SUCCESS
```

### 3.4 发新版本 APK

1. `cp 新APK website/downloads/TaWorld-vX.Y.Z-arm64-v8a.apk`（不进 git）
2. `gh release create vX.Y.Z "website/downloads/TaWorld-vX.Y.Z-arm64-v8a.apk" --title ... --notes ...`
3. 改 `index.html`：搜索 `v0.1.1`，更新版本号、日期、体积、更新日志 details 块、下载文件名（**共 2 处 href**）
4. gh-pages 的 sed 命令里同步换成新 Release URL
5. 三端部署，CloudBase 会把新 APK 一并上传

### 3.5 图片资产再生成（如有新素材）

源图在 `app/assets/images/`（1024px PNG，**无透明通道**——这是"托板"设计的原因）。压缩命令模板：
`magick 源.png -resize 620x620 -quality 85 -define webp:method=6 assets/img/输出.webp`
favicon/apple-touch-icon 源自 `mipmap-xxxhdpi/ic_launcher.png`（**不是** `app/web/icons/Icon-512.png`，那是旧蓝色图标，禁用）。

---

## 四、设计系统速查

### 色彩 tokens（`:root`）

- 基底：`--bg0:#150C09 / --bg1 / --bg2 / --card:#241610 / --card-2 / --raise`
- 文字：`--text:#F5E6DF`（奶油）/ `--mut:#C0A296` / `--faint:#8F776B`
- 强调：`--coral:#E8998D`、`--coral-deep:#B44A3B`（CTA）、`--gold:#C2913D`、`--gold-lt:#DCB26A`
- 五套应用主题色（打字机调色与主题实验室共用）：珊瑚 `#E8998D`、薰衣草 `#9B8EC4`、海洋蓝 `#5B98C4`、樱花粉 `#E88DAA`、森林绿 `#7EAA88`

### 电影分幕（每个 section 的 `--acc`）

| section id | 幕 | 场景类 | 主色 |
|---|---|---|---|
| `#who` | 第一幕 · 念 | （默认） | 珊瑚 |
| `#features` | 第二幕 · 护 | `.sc-gold` | 金 |
| `#memory` | 第三幕 · 忆 | `.sc-lav`（偏紫底 + `.head-center`） | 薰衣草 |
| `#graph` | 第四幕 · 图 | `.sc-blue`（偏蓝底 + `.head-center`） | 海洋蓝 |
| `#reminders` | 第五幕 · 醒（含第六幕 · 礼） | `.sc-sakura` | 樱粉 |
| `#privacy` | 第七幕 · 诺 | `.sc-void`（近黑） | 暗金 |
| `#download` | 第八幕 · 启 | `.sc-ember` | 余烬红 |
| `#faq` | 问 | （默认） | 珊瑚 |

`--acc` 驱动：章节编号描边、eyebrow、act-tag、图标底色（`.b-ico`）、卡片悬停边框、幽灵大字颜色、标题辉光、`.gld` 渐变字。**改某幕氛围只需动这一处。**

### 排版构件

- 章节头 `.chapter-head`：`.chapter-no`（描边大数字）+ `.act-tag`（场记板胶囊）+ `.eyebrow`（拉丁小标）+ `h2`（衬线，幕布揭示 + 辉光）
- `.ghost`：每幕背景巨型汉字（念/护/忆/图/醒/诺/启/问，7% 透明度、随幕色、有滚动视差）；`.ghost-l` 换到左侧
- `.plate`：奶油色画框托板，**所有无透明通道的插画必须放托板里**再上深色卡片
- 字体栈：标题衬线 `"Noto Serif SC","Source Han Serif SC","Songti SC","STSong",Georgia,"SimSun",serif`；正文 `"PingFang SC","Microsoft YaHei","Noto Sans SC",system-ui,...`

### 图标系统

`<svg><defs>` 内约 25 个 `<symbol id="i-*">`，统一 `stroke:currentColor; stroke-width:1.7`。用法 `<svg class="ic"><use href="#i-arrow"/></svg>`。需要新图标就照这个风格手绘 path，不要引入图标字体/CDN。

---

## 五、页面结构地图（自上而下）

1. **导航 `.nav`**：常驻夜色；滚动后加深色玻璃底；底部滚动进度条；移动端汉堡抽屉
2. **Hero `.hero`**：星空（JS 生成 52 星）+ 流星×2 + 月亮 + 虚线轨道；左侧文案 + 异色打字机标题 `#heroTitle`；右侧手机展台（三屏轮播：小念对话/星座图/通知闭环；吉祥物卡；3D 倾斜跟随；滚动视差）
3. **跑马灯 `.marquee`**：产品原则循环横滚（内容 JS 加倍 ×4）
4. **01 念**：三人群卡（托板插画）+ 痛点清单
5. **02 护**：Bento 功能网格（深红主卡 + 聚光灯 hover + 金线扫过）
6. **03 忆**：四层记忆卡（壹贰叁肆描边号）+ 对话演示（统一宽气泡、打字中动画、可重播）
7. **04 图**：夜空星座图（双脉冲核心、行进虚线连线、四节点悬停/点击信息卡、旋转轨道环、内部星空）+ 统计带（数字滚动 30/5/7/169）
8. **05 醒**：可交互通知闭环演示（三按钮状态机 + 呼吸脉动引导）+ 步骤 + 天气四卡（托板）+ 06 礼：徽章墙（光泽掠过）+ 火焰进阶 + 主题实验室（五色实时预览）
9. **07 诺**：隐私深色面板（五原则 + 架构流向 + 承诺横幅）
10. **08 启**：深色下载面板（规格 chips、双按钮、浅色侧卡）+ 更新手风琴
11. **问答**：FAQ 手风琴（grid-rows 平滑展开）
12. **尾声 `.finale`**：异色打字机大标题（进入视口开演）
13. **页脚**：链接 + 巨型描线签名 "TaWorld"
14. **全局浮层**：`.vignette` 镜头暗角、`.lantern` 提灯、`.act-rail` 章节选单轨（<1180px 隐藏）、`.totop` 回顶

---

## 六、交互与 JS 清单（都在 `index.html` 底部单个 IIFE 里）

| 功能 | 机制 | 备注 |
|---|---|---|
| **打字机引擎 `typeCycle()`** | 拆字成 `.ch` span，逐字 `.on`（90ms）→ 停 3.2s（光标闪烁）→ 逐字删（45ms）→ 停 0.8s → 循环 | 首屏 `#heroTitle`（载入 500ms 后开打）与结尾 `#finaleTitle`（IO 进入视口后开打）共用；跳过 `<br>`；reduced-motion 直接全显 |
| 滚动显现 `.reveal` | IntersectionObserver（threshold .12，rootMargin -6%） | **见 §8 伪影警告** |
| 章节轨 `#actRail` | JS 按 `railDefs` 生成 8 项；独立 IO 高亮当前幕 | 点击锚点跳转 |
| 提灯 `#lantern` | 全视口固定层，`backgroundPosition` 随鼠标 rAF-lerp（0.085） | 仅 `pointer:fine` 且非 reduced；**不要改回 transform 位移方案**（窄视口会撑滚动度量，见 §8） |
| 幽灵视差 | scroll 时按 `±0.07×距视口中心` 设置 `.ghost` translateY | |
| 按钮涟漪 | `.btn` pointerdown 注入 `.ripple` span，700ms 后移除 | |
| 通知脉动 | `.notif.pulsing` 呼吸描边；任一按钮首次点击移除 | |
| 主题实验室 | 点击色丸设置 `--tp/--tp-deep` 与预览卡背景 | `color-mix()` 需要 Chrome 111+/Safari 16.2+，2026 年无兼容问题 |
| 图谱信息卡 | 悬停/点击钉住（`pinned`）；上半区节点卡在下、下半区卡在上；边界夹取；点外部收起 | **不许加回任何心形图标**（用户两次点名） |
| 数字滚动 | IO 触发，`1-(1-p)^3` 缓动 1.4s | 30/5/7/169 |
| 手机轮播 | 3.8s 自动切换 + 圆点点击 | |
| 手机 3D 倾斜 | stage pointermove → rotateX/Y ≤9° | pointer:fine |
| Hero 视差 | scroll：手机 `translate` 0.08、文案 opacity 渐隐 | |
| 星空/流星 | JS 生成 `.star`（随机位置/尺寸/延迟）；流星纯 CSS | hero 52 颗、图谱 26 颗 |
| 其余 | scrollspy、进度条、菜单、跑马灯加倍、FAQ/更新手风琴（CSS grid-rows）、回顶、背景光斑鼠标视差 | |

所有动效都被全局 `@media (prefers-reduced-motion: reduce)` 降级——新增动效必须确认这条仍然覆盖它。

---

## 七、验证清单（每次改版后跑一遍）

```bash
cd website && python -m http.server 8132   # 本地预览 http://localhost:8132
```

浏览器（Playwright 或手动）：
- [ ] 桌面 1440 与移动 390 全页截图，无破图、无乱码、无横向滚动（390 下 `window.scrollTo(80,0)` 后 `scrollX===0`）
- [ ] emoji 扫描零输出（§9 命令）
- [ ] 打字机：首屏开打、结尾进入视口后开打、循环往复
- [ ] 图谱四节点：悬停/点击信息卡不遮节点、无心形
- [ ] 对话气泡等宽；通知三按钮各有回应；主题五色可切换；章节轨随滚动高亮
- [ ] 章节头（含居中两款）标题全部可见
- [ ] APK 链接：本地 200；线上 CloudBase `/downloads/...` content-length=56004083（v0.1.1 时）
- [ ] reveal 伪影：如需程序化测试，必须"逐元素位置 instant 滚动 + 停留 1s"，不要用连续 scrollTo 快扫（见 §8）

---

## 八、已知的坑（前辈踩过的雷）

1. **Mimosa 安全钩子**：本机在 git commit 前对全仓库扫描，发现 high 级（如硬编码凭据）会**在工具层强制拦截**，`--no-verify` 无效，必须真修复被点名的文件。历史上已修复 `server/tests/` 的哑密码（改为 `secrets` 随机生成，见 commit `80e8b78`）。另：它时常报 `python_ast_unavailable` 然后放行——那是它自己的兼容策略，不代表你的提交被审计过了。
2. **LOGO 源文件**：`app/web/icons/Icon-512.png` 是旧版蓝色图标，**永远不要用它**。正确源：`app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`。
3. **gh-pages worktree**：分支已存在，`git worktree add --orphan -b gh-pages` 会报错；直接 `git worktree add <路径> gh-pages`。用完 `git worktree remove --force`。
4. **Pages 缓存**：push 后构建约 1 分钟 + CDN 数分钟；`?v=N` 参数绕过验证。
5. **scroll-behavior:smooth**：让程序化 `scrollTo` 变成动画，快速循环滚动会"跳过"大量位置，IntersectionObserver 不触发——**这是测试伪影不是 bug**。程序化测试一律 `behavior:'instant'` 且每步停留。
6. **横向溢出度量**：`documentElement.scrollWidth` 可能因固定层（提灯旧实现）虚高；判断标准是"用户能否滚动"（scrollX）。提灯已改为全视口背景层方案，别改回去。`html` 与 `body` 都有 `overflow-x:hidden` 双保险。
7. **CloudBase 域名**：以 deployApp 返回的 accessUrl 为准，别手拼。
8. **og:image 必须绝对 URL**（现指向 CloudBase 域名下的 og-banner.png）。
9. **首屏标题动画**：用户对"滚动后才出现的文字"非常敏感（描述为"点击拖动鼠标才能出现"）。重要标题一律用打字机引擎；若加新的标题动效，确保**页面加载即可见**或有打字过程。

---

## 九、命令速查

```bash
# emoji / 危险字符扫描（零输出为合格）
perl -CSD -ne 'while (/([\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2190}-\x{21FF}\x{2B00}-\x{2BFF}\x{FE0F}\x{2764}])/g){print "$.: $1\n"}' website/index.html

# 本地预览
cd website && python -m http.server 8132

# 三端部署：见 §3.3 / §3.1

# 线上验证
curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" https://taworld-cloud1-8grf0qgi8c6c0603.webapps.tcloudbase.com/
curl -sI https://taworld-cloud1-8grf0qgi8c6c0603.webapps.tcloudbase.com/downloads/TaWorld-v0.1.1-arm64-v8a.apk | head -3
curl -s "https://ghostllc.github.io/TaWorld/?v=$(date +%s)" | grep -c "releases/download"   # 应为 2
```

---

## 十、还欠着的事（未来维护者的机会清单）

- **真实应用截图**：仓库里没有 app 截图，Hero 手机与各 mockup 全是 CSS/SVG 手绘。截真图替换会显著提升可信度（注意深色模式下截图更配本站）。
- **正式签名**：APK 目前是调试签名（FAQ 与下载说明已如实标注）。换正式签名后记得删掉那句提示。
- **iOS**：应用上 iOS 后，下载区加对应区块，FAQ 更新。
- **自定义域名**：CloudBase 绑自定义域名需 ICP 备案；备案下来后 `manageGateway bindCustomDomain`。
- **版本历史**：更新日志目前手写两块；版本多了可考虑从 GitHub Releases API 动态拉（注意：会引入外部请求，需评估对"大陆秒开"的影响——拉取失败要静默降级到手写内容）。
- 声音、WebGL 粒子这类更重的效果都评估过并主动放弃（性能/气质不符）；除非用户点名，不建议加。

---

*本文件随官网一起演进。每次大改后请更新 §二 的版本表与 §五 的结构地图。*
