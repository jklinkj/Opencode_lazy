# OpenCode Online Installer

This repository contains the online download and installation scripts for the OpenCode deployment package.
It only stores scripts, manifests, launchers, and configuration templates. Third-party installers and binary payloads are downloaded at install time and are not redistributed in this repository.

## Download policy

- Default strategy: official sources first, mainland China mirrors as fallback.
- Download order and checksum rules are defined in `manifests/downloads/lingnan-admin-v1.jsonc`.
- School or self-hosted mirrors can be added as whitelist entries in the same manifest.
- All downloaded files are stored in `runtime/download-cache/` and verified with SHA-256 before use.

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
