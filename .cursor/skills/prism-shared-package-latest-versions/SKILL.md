---
name: prism-shared-package-latest-versions
description: 用 Azure CLI（azure-devops 扩展）调用 ADO Packaging API，按 Shared 目录 nuspec 列出各内部包在目标 feed 上的最新版本，写入 doc/shared-package-versions.json；需 az login。
---

# Shared 包最新版本（ADO Artifacts）

## 何时使用

- 用户要 **查询 / 对齐 Shared 相关 NuGet 包在 ADO 上的最新版本**，或生成 **Package | Version** 表。
- 需要 **可重复** 结果：运行 `scripts/get-shared-package-latest-versions.ps1`，勿手抄。

## 前置条件

1. **Azure CLI**：<https://aka.ms/installazurecliwindows>
2. **扩展**：`az extension add --name azure-devops`
3. **`az login`**，且账号对组织 **`slb1-swt`** 及目标 **Artifacts feed**（默认 **PrismService**）有读权限。

脚本使用 **`az devops invoke`** 访问 Packaging REST（与在浏览器中查看 Artifacts 同源），**不依赖** `az account get-access-token --resource 499b84ac-…` / NuGet v3 Bearer。对每个 nuspec 包 ID 使用 **`packageNameQuery`** 查询，避免 feed 内包数量很大时仅拉到前 1000 条导致漏包。

## 一键执行

仓库根目录：

```powershell
.\scripts\get-shared-package-latest-versions.ps1
```

- 从 **`Shared/**/*.nuspec`** 读取 `<id>` 作为包 ID 列表。
- 配置见 **`scripts/shared-package-feed-config.json`**（`organizationUrl`、`feedName`，默认 **PrismService**）。
- 输出 **`doc/shared-package-versions.json`**（UTF-8 BOM）。

可选：`-OutMarkdownPath '.\doc\shared-package-versions.md'` 生成 Markdown 表。

## 输出 `doc/shared-package-versions.json`

| 字段 | 含义 |
| --- | --- |
| `generatedAt` | UTC 时间 |
| `organizationUrl` | ADO 组织 URL |
| `feedName` / `feedId` | 使用的 feed |
| `packages` | `packageId`、`latestVersion`（API 中带 `isLatest` 的版本）、`error`（feed 中未匹配时） |

## 故障排查

| 现象 | 处理 |
| --- | --- |
| 缺少 azure-devops 扩展 | `az extension add --name azure-devops` |
| invoke 失败 / 401 | `az login`，确认能打开 `dev.azure.com/slb1-swt` 且对 feed 有读权限 |
| 某包 `error` 非空 | 包未推入该 feed，或名称与 nuspec `<id>` 不一致 |
