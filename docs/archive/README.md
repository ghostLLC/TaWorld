# 历史归档说明

本目录保留 TaWorld 演进过程中的旧架构、研究和方案，用于追溯决策，**不构成现行产品需求或开发依据**。

## server/

FastAPI/PostgreSQL 后端时代的架构、实现对比、开发指南和验收记录。该后端已经废弃，当前 App 不需要它。文档中出现的 JWT、FCM、MinIO、Redis、双人云端关系和旧数据库结构只代表历史实现。

## research/

研究、优化设想和阶段性方案，包括模型缓存、单机改造、备份、AI 记忆、主动关心、飞书知识库和视觉素材升级。

这些文件可能描述已完成、部分完成或未采用的想法。是否属于现行功能，只能以 `app/` 代码、根 AGENTS 和现行文档为准。

`asset_upgrade_plan.md` 中的透明背景、无文字、按尺寸导出等素材方向目前暂缓实施；品牌角色、图片和水印不在本轮修改范围内。

## superpowers/plans/

`docs/superpowers/plans/` 继续保留历史实施计划，用于查看当时任务范围与验证过程，不移动到本目录是为了保留现有路径与工具链接。

## 使用规则

- 可以从归档理解“为什么这样做”，不要用归档证明“现在就是这样”。
- 归档中的 Riverpod、Hive、FCM、wttr.in、Pro/独立视觉模型、旧测试数量和旧版本状态均可能过时。
- 当前唯一模型是 `deepseek-flash`，当前 UI 使用 StatefulWidget/setState，天气使用 Open-Meteo，数据库为 SQLite schema v7。
