# TaWorld 官网维护指引（AI 自动加载入口）

维护本目录前，**必须先完整阅读 [HANDOFF.md](./HANDOFF.md)**——它是唯一的权威交接文档，包含：

- 来龙去脉（v1→v6 每一版驱动它的用户反馈，决定了用户的审美取向）
- 硬性规则（禁 emoji、零外部依赖、图标必须用 `mipmap/ic_launcher.png`、气泡统一宽度、星座图禁心形等，违反即事故）
- 设计系统速查（夜色色板、八幕电影分幕调色表、组件与交互实现要点）
- 三端部署流程（master / gh-pages sed 改写 / CloudBase MCP 命令）与发版 checklist
- 测试清单（含 headless IO 伪影、Mimosa commit 钩子等踩坑记录）

速记：本地预览 `python -m http.server 8123`；改版后必须跑 HANDOFF.md 第六节测试清单再上线。
