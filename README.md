# Prism PA Workspace

本仓库包含 Prism 算法平台改造过程中的 Actor、Shared、Pipeline 与辅助脚本。

## Scripts

脚本说明统一维护在 `doc/scripts.md`。

### export-package-versions.ps1

`scripts/export-package-versions.ps1` 用于扫描 `Actors` 和 `Shared` 下各工程的 NuGet 依赖版本，并在 `doc/package-versions.md` 中生成：

- 包名、版本、来源仓库汇总表。
- 每个包各版本的引用仓库与工程明细。

示例：

```powershell
.\scripts\export-package-versions.ps1
```

```powershell
.\scripts\export-package-versions.ps1 -RootPath D:\SLB\Prism\PA -OutputPath .\doc\package-versions.md
```
