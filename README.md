# Opencode_lazy

English | [中文说明](#中文说明)

This repository contains the online download and installation scripts for the OpenCode deployment package.
It stores scripts, manifests, launchers, and configuration templates only. Third-party installers and binary payloads are downloaded at install time and are not redistributed in this repository.

## What this repository includes

- PowerShell install and repair scripts
- Download manifests and checksum rules
- Launcher entrypoints for Windows deployment
- Academy configuration templates for OpenCode

## Download policy

- Official sources first, mainland China mirrors as fallback
- Source order is defined in `manifests/downloads/lingnan-admin-v1.jsonc`
- Downloaded files are stored in `runtime/download-cache/`
- All artifacts must pass SHA-256 verification before installation

## Entrypoints

- `launcher/start.cmd`
- `launcher/scan-only.cmd`
- `launcher/configure-opencode.cmd`
- `launcher/open-opencode-web.cmd`
- `launcher/install-desktop.cmd`

## Build a release package

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-package.ps1 -CreateZip
```

## 中文说明

这个仓库用于分发 OpenCode 的在线下载安装脚本。
仓库只包含脚本、清单、启动器和配置模板，不直接分发第三方安装包或二进制文件，以避免开源仓库中的再分发合规问题。

## 仓库内容

- Windows PowerShell 安装、检测与修复脚本
- 在线下载清单与校验规则
- 一键启动入口 `launcher/*.cmd`
- OpenCode 学院侧配置模板

## 下载策略

- 默认优先使用官方源，国内镜像作为兜底
- 下载顺序定义在 `manifests/downloads/lingnan-admin-v1.jsonc`
- 下载文件统一落到 `runtime/download-cache/`
- 所有安装包在使用前都会进行 SHA-256 校验

## 常用入口

- `launcher/start.cmd`：执行完整安装流程
- `launcher/scan-only.cmd`：只做环境扫描，不安装
- `launcher/configure-opencode.cmd`：写入配置模板
- `launcher/open-opencode-web.cmd`：打开 OpenCode Web
- `launcher/install-desktop.cmd`：安装 Desktop 客户端

## 打包命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-package.ps1 -CreateZip
```
