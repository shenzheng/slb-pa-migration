# Prism PA Workspace

本仓库用于维护 Prism 算法平台改造过程中的 Actor、Shared、Pipeline 辅助文档与自动化脚本。

## Scripts

脚本详细说明统一维护在 `doc/scripts.md`。下面保留当前阶段最常用脚本的快速入口。

### export-package-versions.ps1

`scripts/export-package-versions.ps1` 用于扫描 `Actors` 和 `Shared` 下各工程的 NuGet 依赖版本，并生成 `doc/package-versions.md`。

```powershell
.\scripts\export-package-versions.ps1
```

```powershell
.\scripts\export-package-versions.ps1 -RootPath D:\SLB\Prism\PA -OutputPath .\doc\package-versions.md
```

### export-package-target-baseline.ps1

`scripts/export-package-target-baseline.ps1` 用于读取 `doc/package-versions.md`，结合 `tasks/task-5-uni-pkg-version.md` 的排除清单，生成统一包版本升级的目标基线文档 `tasks/uni-pkg-version-target-baseline.md`。

```powershell
.\scripts\export-package-target-baseline.ps1
```

```powershell
.\scripts\export-package-target-baseline.ps1 -RootPath D:\SLB\Prism\PA -OutputPath .\tasks\uni-pkg-version-target-baseline.md
```

```powershell
.\scripts\export-package-target-baseline.ps1 -ExcludedRepositories Rhapsody.Service.StreamSampling,Rhapsody.Service.ActorDirector
```

### find-package-version-conflicts.ps1

`scripts/find-package-version-conflicts.ps1` 用于读取 `doc/package-versions.md`，输出当前仍存在多版本并存的包，方便人工 review 和后续登记计划内例外。

```powershell
.\scripts\find-package-version-conflicts.ps1
```

```powershell
.\scripts\find-package-version-conflicts.ps1 -OutputPath .\tasks\uni-pkg-version-conflicts.md
```

```powershell
.\scripts\find-package-version-conflicts.ps1 -ExceptionPath .\doc\package-version-conflict-exceptions.md
```

### extract-pipeline-package-version.ps1

`scripts/extract-pipeline-package-version.ps1` 用于从 Azure DevOps 构建标题、日志片段或其他文本输入中提取真实包版本，默认输出纯版本字符串，适合被后续脚本直接消费。

当没有传入有效输入，或者输入中找不到版本时，脚本会返回非零退出码，便于流水线直接判失败。

```powershell
.\scripts\extract-pipeline-package-version.ps1 -Text "HydraulicsTransient package #1.0.0.15601898 published"
```

```powershell
.\scripts\extract-pipeline-package-version.ps1 -InputPath .\tasks\pipeline-build-log.txt -AsJson
```

### verify-package-upgrade.ps1

`scripts/verify-package-upgrade.ps1` 用于对指定仓库目录执行统一包版本升级前后的基础验证框架检查，当前支持 `dotnet restore`、`dotnet build`、可选 `test`、CRLF 检查，以及“项目包引用与 `.nuspec metadata/dependencies` 依赖版本一致性”检查。

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient
```

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient -RunTest -AsJson -OutputPath .\tasks\verify-hydraulics-transient.json
```
