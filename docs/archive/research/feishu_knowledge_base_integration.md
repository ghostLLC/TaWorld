# 飞书知识库连接与复用指南

本文记录 Codex 连接、读取和管理飞书知识库的稳定做法，供 TaWorld 及后续其他知识库复用。文中不保存 App Secret、访问令牌、刷新令牌或真实授权链接。

## 1. 当前方案

采用“官方读取能力 + 固定版本编辑适配层 + 飞书官方 OpenAPI 校验”的组合：

- 官方 MCP：用于常规读取和导入能力。
- `feishu-mcp@0.3.2`：补充知识库节点创建、云文档块编辑等能力；固定版本，避免未经评估的自动升级。
- 用户 OAuth：以当前飞书用户身份访问其有权限的知识空间。
- 飞书官方 OpenAPI：在 MCP 工具异常时用于最小化诊断、读写和回读校验。

本机入口脚本：

- `C:\Users\LLC\.codex\bin\start-feishu-mcp.ps1`
- `C:\Users\LLC\.codex\bin\start-feishu-edit-mcp.ps1`

## 2. 飞书应用配置

在飞书开发者后台创建“企业自建应用”，申请与实际用途匹配的用户权限。知识库管理至少需要覆盖：

- 查看、编辑和管理知识库；
- 读取、创建和编辑新版云文档；
- 必要的云空间文件读取/写入能力；
- `offline_access`，用于刷新用户访问令牌。

在“安全设置 → 重定向 URL”中同时添加：

```text
http://localhost:3000/callback
http://localhost:3333/callback
```

`3000` 供官方 MCP 使用，`3333` 供当前编辑适配层使用。保存权限或回调配置后，必须发布应用版本，直到后台显示“当前修改均已发布”。

## 3. 本机凭证与 MCP 注册

凭证只保存在 Windows 用户级环境变量中：

```text
FEISHU_MCP_APP_ID
FEISHU_MCP_APP_SECRET
FEISHU_EDIT_MCP_USER_KEY
```

`FEISHU_EDIT_MCP_USER_KEY` 是稳定的本地用户标识，用于找到同一份 OAuth 缓存。不要把上述变量值写进仓库、Markdown、聊天记录或启动脚本。

MCP 注册方式：

```powershell
codex mcp add feishu -- powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\LLC\.codex\bin\start-feishu-mcp.ps1
codex mcp add feishu-edit -- powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\LLC\.codex\bin\start-feishu-edit-mcp.ps1
```

启动脚本从用户环境变量取值，避免在 Codex 配置文件中出现明文 Secret。

## 4. 首次 OAuth 授权

当编辑工具首次调用文档能力时，会在浏览器打开飞书授权页，并在本机启动 `3333` 回调服务。授权完成后，令牌缓存位于：

```text
C:\Users\LLC\.cache\feishu-mcp\user_token_cache.json
```

该文件包含敏感令牌和客户端凭证，不得提交 Git、复制到知识库或发送给他人。

可用一次只读调用触发并验证授权：

```powershell
$env:FEISHU_APP_ID = [Environment]::GetEnvironmentVariable('FEISHU_MCP_APP_ID', 'User')
$env:FEISHU_APP_SECRET = [Environment]::GetEnvironmentVariable('FEISHU_MCP_APP_SECRET', 'User')
$env:FEISHU_AUTH_TYPE = 'user'
$env:FEISHU_ENABLED_MODULES = 'document'
$env:FEISHU_USER_KEY = [Environment]::GetEnvironmentVariable('FEISHU_EDIT_MCP_USER_KEY', 'User')
npx -y -p feishu-mcp@0.3.2 feishu-tool get_feishu_root_folder_info '{}'
```

授权链接的 `state`、`code` 和完整 URL 同样视为敏感信息，不应粘贴到聊天或日志中。

## 5. 连接新知识库

飞书知识库链接通常包含：

```text
https://<tenant>.feishu.cn/wiki/space/<space_id>
```

其中 `<space_id>` 是知识空间标识。连接新的知识库时按以下顺序执行：

1. 用用户令牌读取 `/wiki/v2/spaces/<space_id>/nodes`，确认空间可访问。
2. 列出根节点和目标父节点的现有子节点，记录标题、`node_token`、`obj_token` 和类型。
3. 按标题查重；存在则更新，不存在才创建，保证重复执行不会生成副本。
4. 创建知识库节点后，用返回的 `obj_token` 调用 Docx Block API 写正文。
5. 写入后重新读取节点树、块数量和关键标题，确认层级、内容及重复项。
6. 只同步项目状态、关键决策、里程碑、质量结论、风险和永久产物链接；代码细节仍以 Git 为准。

推荐的通用知识库结构：

```text
首页 / 项目总览
├─ 01｜产品设计与交互决策
├─ 02｜技术架构与开发环境
├─ 03｜开发日志
├─ 04｜版本发布与构建产物
├─ 05｜测试与质量报告
├─ 06｜风险、技术债与待办
└─ 07｜关键决策 ADR
```

## 6. 常见问题

### 错误码 20029：重定向 URL 有误

原因通常是授权请求中的回调地址没有与开发者后台完全一致。检查 `3000` 和 `3333` 两个地址是否已添加，并确认应用版本已经发布。

### 浏览器显示授权成功，但命令行没有退出

这是当前社区适配层可能出现的本地回调进程收尾问题。先确认令牌缓存是否生成，再终止本次启动的具体回调进程；不要批量结束所有 Node 或 MCP 进程。

### `refresh_token_expires_in` 只有 168 小时

这是刷新令牌的滚动窗口，不等于每七天固定重新登录。当前适配层会在访问令牌即将到期时刷新并缓存新令牌。连续超过七天完全未使用、撤销授权、修改权限、轮换 Secret 或删除缓存后，可能需要重新授权。

### 能读取但不能编辑

依次确认：

1. 应用已申请并发布编辑权限；
2. 当前用户对目标知识库/文档本身拥有编辑权限；
3. 使用的是用户 OAuth，而不是权限范围不足的租户令牌；
4. 知识库节点的 `obj_token` 被当作文档 `document_id` 使用。

## 7. 安全与维护

- App Secret 一旦出现在聊天、日志或仓库中，应立即轮换。
- 轮换 Secret 后，更新本机用户环境变量，清除旧 OAuth 缓存并重新授权；不要直接手改缓存中的令牌。
- 固定社区依赖版本，升级前检查变更、权限范围和令牌缓存逻辑。
- 不在知识库中上传本地 APK 路径；正式产物应使用 GitHub Release 或对象存储的永久链接。
- 每次自动同步后都执行回读验证，不以“API 返回成功”代替最终内容检查。

## 8. 最小验收清单

- [ ] 目标 `space_id` 可读取
- [ ] 根节点和已有页面已列出
- [ ] 写入前完成标题查重
- [ ] 页面层级正确
- [ ] 文档正文可回读
- [ ] 不存在重复标题
- [ ] 未输出或提交任何 Secret、access token、refresh token、OAuth state/code
- [ ] 应用配置修改已经发布
- [ ] 重要更新已记录日期、分支/提交、测试结论、产物与风险
