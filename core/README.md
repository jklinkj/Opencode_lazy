# opencode-installer-core

Shared installer core for the offline and online projects.

- `modules/`: reusable PowerShell modules for checks, repairs, deployment, reports, profile loading, and download orchestration
- `schemas/`: shared JSON schema files for installer profiles and download manifests

Standalone project packages should vendor `core/modules` next to the project root so launcher scripts can resolve the shared modules without the full workspace.