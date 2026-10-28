# TaWorld 产品官网

单文件纯静态官网（`index.html`），零外部依赖：不引用网络字体、第三方 CDN 或外部脚本，图片全部本地化，适合中国大陆访问。

维护前必须先阅读 **[HANDOFF.md](HANDOFF.md)**：它记录视觉决策、硬性规则、设计系统、部署流程和测试清单。

## 目录结构

```text
website/
├── index.html              # 单页官网（内联 CSS/JS）
├── assets/img/             # 本地图片与图标
├── downloads/              # APK 下载文件（不入 Git）
│   └── TaWorld-v0.2.0-arm64-v8a.apk
├── .gitignore
├── README.md               # 本文件
└── HANDOFF.md              # 详细维护交接
```

## 本地预览

```bash
cd website
python -m http.server 8123
# 浏览器打开 http://localhost:8123
```

建议通过 HTTP 预览，以验证相对 APK 下载链接。

## 部署摘要

- **CloudBase**：整个 `website/` 目录（含 downloads）部署，APK 使用相对路径。具体 MCP 参数见 HANDOFF 第五节。
- **任意静态服务器/对象存储**：上传整个目录即可，无构建步骤。
- **GitHub Pages**：使用 gh-pages 分支；复制页面和图片后，将下载链接改写为 GitHub Release 附件地址，不在分支中存放大型 APK。

## 更新版本

1. 将新 APK 复制为 `downloads/TaWorld-vX.Y.Z-arm64-v8a.apk`。
2. 更新 `index.html` 的版本、日期、体积、下载链接和更新日志。
3. 创建 GitHub Release 并上传各 ABI 安装包。
4. 按 HANDOFF 清单完成桌面、移动端、交互和链接验证。
5. 只有用户明确要求时，才部署 CloudBase 或 gh-pages。

当前版本为 **v0.2.0（2026-10-28）**。APK 继续使用项目既有调试签名，覆盖升级需要保持同一证书并递增 versionCode。
