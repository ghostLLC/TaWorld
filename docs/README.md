# TaWorld 文档索引

本目录区分**现行文档**与**历史归档**。阅读顺序为：根 `AGENTS.md` → 根 `README.md` → 本索引 → 对应专题文档 → 现行代码与测试。

## 现行文档

| 文档 | 用途 |
| --- | --- |
| [architecture.md](architecture.md) | 当前单机 Flutter 架构、模型、数据、通知、隐私与后台任务 |
| [frontend_guide.md](frontend_guide.md) | 当前页面、组件、主题、异步状态、可访问性与动效约定 |
| [design_system.md](design_system.md) | 色板、字体、间距、圆角、组件与视觉规范 |
| [development_environment.md](development_environment.md) | Flutter/JDK/Gradle 版本、统一开发入口与网络环境 |
| [testing.md](testing.md) | 验证命令、225 项测试基线、覆盖范围与证据边界 |
| [design-audit/2026-10-28-frontend-review.md](design-audit/2026-10-28-frontend-review.md) | 前端问题、已实施修复及仍需视觉验收的事项 |
| [releases/v0.2.0.md](releases/v0.2.0.md) | v0.2.0 发布说明与资产范围 |

仓库根文档：

- `AGENTS.md`：AI 与开发者的工作规则、业务边界和维护红线。
- `README.md`：产品能力、版本、下载、开发和验证概览。
- `LICENSE`：MIT 许可证。
- `website/README.md`：官网快速预览与部署摘要。
- `website/HANDOFF.md`：官网视觉规则、历史决策和详细维护流程。

## 历史归档

- [archive/server/](archive/server/)：已废弃 FastAPI/PostgreSQL 后端的设计、对比和验收记录。
- [archive/research/](archive/research/)：已实施或未实施的研究、方案与优化设想。
- [superpowers/plans/](superpowers/plans/)：历史实施计划，保留用于追溯决策。

归档内容**不是现行产品规格**。其中出现的 Riverpod、Hive、FCM、wttr.in、Pro/独立视觉模型、双人云端关系或旧测试数量，均不得覆盖当前实现。

## 当前代码目录

- `app/`：唯一现行 App，Flutter Android、SQLite schema v7。
- `app/packages/taworld_notifications/`：Android 原生通知插件。
- `tool/taworld.ps1`：统一开发环境入口。
- `website/`：零外部依赖的静态产品官网。
- `server/`：废弃参考实现，不运行、不修改。
- `competition/`：本地历史提案，不是现行需求。
