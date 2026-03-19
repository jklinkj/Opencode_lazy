# OpenCode Online Installer

这个项目是在线下载和安装项目源码。GitHub 仓库只存放脚本、清单、配置模板和校验值，不分发第三方安装包本体。

## 下载策略

- 默认策略：官方源优先，国内镜像兜底。
- 具体源顺序写在 `manifests/downloads/lingnan-admin-v1.jsonc`。
- 学校或自建镜像默认留空位，按需启用。
- 所有下载文件会落到 `runtime/download-cache/`，并执行 SHA-256 校验。

## 项目入口

- `launcher/start.cmd`
- `launcher/scan-only.cmd`
- `launcher/configure-opencode.cmd`
- `launcher/open-opencode-web.cmd`
- `launcher/install-desktop.cmd`

## 构建在线包

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-package.ps1 -CreateZip
```