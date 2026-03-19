# 在线下载源策略

在线项目只分发脚本和清单。

- 官方源优先
- 中国大陆镜像兜底
- 学校镜像预留白名单入口
- 每个 artifact 都必须通过 SHA-256 校验

修改下载顺序时，只改 `manifests/downloads/lingnan-admin-v1.jsonc`，不要把站点硬编码回脚本。