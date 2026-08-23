# TaWorld 产品官网

单文件纯静态官网（`index.html`），**零外部依赖**：不引用 Google Fonts、不使用任何第三方 CDN，全部图片本地化并压缩为 WebP（合计约 150KB + OG 图 1.1MB），适合中国大陆境内快速打开。

> 维护前必读：**[HANDOFF.md](HANDOFF.md)** —— 完整的来龙去脉、设计系统、部署流程、红线规则与踩坑记录。

## 目录结构

```
website/
├── index.html              # 官网单页（内联 CSS/JS）
├── assets/img/             # 压缩后的图片（WebP）+ favicon + og-banner
├── downloads/              # APK 下载（不入库，见 .gitignore）
│   └── TaWorld-v0.1.1-arm64-v8a.apk
├── .gitignore              # 忽略 APK 大文件
└── README.md
```

## 本地预览

```bash
cd website
python -m http.server 8123
# 浏览器打开 http://localhost:8123
```

直接双击 `index.html` 也可以打开，但建议走本地 HTTP 服务以验证 APK 下载链接。

## 部署

### 方式一：腾讯云 CloudBase 静态托管（推荐，大陆访问快）

1. MCP 已接入 CloudBase（`cloudbase` 工具），登录并绑定环境后：
   - `manageApps(action="deployApp", serviceName="taworld", framework="static", installCmd="", buildCmd="", filePath=<website 绝对路径>)`
   - APK 上传到同一环境：`manageStorage(action="upload", localPath=<apk>, cloudPath="downloads/TaWorld-v0.1.1-arm64-v8a.apk")`，并把站点路由的 `/downloads/...` 指向该对象。
2. 默认域名形如 `https://<name>-<envId>.webapps.tcloudbase.com`，大陆直连；绑定自定义域名需 ICP 备案。

### 方式二：任意静态服务器 / 对象存储

把 `website/` 整个目录（含 downloads）上传到 nginx、COS、OSS 等即可，无需构建步骤。

### 方式三：GitHub Pages（海外/备用）

把 `website/` 推到 `gh-pages` 分支或仓库 `/docs`；大陆访问 github.io 不稳定，仅作备用镜像。

## 更新版本时

1. 把新 APK 复制为 `downloads/TaWorld-vX.Y.Z-arm64-v8a.apk`；
2. 更新 `index.html` 中版本号、日期与更新日志（搜索 `v0.1.1`）；
3. 重新部署。
