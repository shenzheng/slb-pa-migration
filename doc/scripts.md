# Scripts 使用说明

## 概述

本文档说明 `scripts` 目录下各个 PowerShell 脚本的用途和用法。

## git-pull-all.ps1

`git-pull-all.ps1` 用于拉取 `Actors` 和 `Shared` 目录下各 Git 仓库当前分支的最新代码。

### 脚本行为

- 使用 `git pull --ff-only`，避免自动生成 merge commit。
- 输出实时进度、当前仓库和每个仓库的处理耗时。
- 处于 detached `HEAD` 状态或未配置上游分支的仓库会被跳过并记录。
- 只要任意仓库拉取失败，脚本会以退出码 `1` 结束。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `ProjectGroups` | 需要扫描的顶层目录。 | `Actors`, `Shared` |

### 示例

```powershell
.\scripts\git-pull-all.ps1
```

```powershell
.\scripts\git-pull-all.ps1 -RootPath D:\SLB\Prism\PA
```

```powershell
.\scripts\git-pull-all.ps1 -ProjectGroups Actors
```

## normalize-crlf.ps1

`normalize-crlf.ps1` 用于将指定目录下符合条件的文本文件统一转换为 Windows `CRLF` 换行。

### 脚本行为

- 扫描 `.cs`、`.csproj`、`.json`、`.md`、`.ps1` 等常见文本文件扩展名。
- 自动排除 `.git`、`bin`、`obj`、`packages` 等常见生成目录或工具目录。
- 仅重写包含纯 `LF` 换行的文件。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 递归扫描的根目录。 | 当前目录 |

### 示例

```powershell
.\scripts\normalize-crlf.ps1 -RootPath D:\SLB\Prism\PA
```

## export-repo-to-nuget-map.ps1

`export-repo-to-nuget-map.ps1` 用于扫描一组仓库中的 `.nuspec` 文件，并生成 repository 与 NuGet 包的映射文档。

### 脚本行为

- 默认扫描 `Actors`、`Shared`、`Pipeline` 三个顶层目录。
- 在每个一层仓库目录下递归查找 `.nuspec` 文件。
- 解析 `.nuspec` 的 `metadata/id` 与 `metadata/version`。
- 生成包含 `Project Group`、`Repository`、`Package Id`、`Version`、`Nuspec Path` 的 Markdown 表格。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `ProjectGroups` | 需要扫描的顶层目录。 | `Actors`, `Shared`, `Pipeline` |
| `OutputPath` | 输出 Markdown 文件路径。 | `doc\repo-to-nuget-map.md` |

### 示例

```powershell
.\scripts\export-repo-to-nuget-map.ps1
```

```powershell
.\scripts\export-repo-to-nuget-map.ps1 -RootPath D:\SLB\Prism\PA
```

```powershell
.\scripts\export-repo-to-nuget-map.ps1 -ProjectGroups Actors,Shared -OutputPath .\doc\actors-shared-repo-to-nuget.md
```

## export-package-versions.ps1

`export-package-versions.ps1` 用于扫描 `Actors` 和 `Shared` 下的工程依赖，收集 NuGet 包版本，并生成带有依赖关系明细的 Markdown 文档。

### 脚本行为

- 默认扫描 `Actors`、`Shared` 两个顶层目录。
- 递归分析工程文件中的 `PackageReference`，并兼容 `packages.config`。
- 支持读取工程目录链上的 `Directory.Build.props` 与 `Directory.Packages.props`。
- 生成 `Package Version Summary` 与 `Package Dependency Details` 两部分结果。
- 自动识别 `Actors` 或 `Shared` 仓库自身产出的包，并在 `Source` 列中标记来源仓库。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `ProjectGroups` | 需要扫描的顶层目录。 | `Actors`, `Shared` |
| `OutputPath` | 输出 Markdown 文件路径。 | `doc\package-versions.md` |

### 示例

```powershell
.\scripts\export-package-versions.ps1
```

```powershell
.\scripts\export-package-versions.ps1 -RootPath D:\SLB\Prism\PA
```

```powershell
.\scripts\export-package-versions.ps1 -ProjectGroups Actors,Shared -OutputPath .\doc\package-versions.md
```

## export-package-target-baseline.ps1

`export-package-target-baseline.ps1` 用于基于 `doc/package-versions.md` 生成统一包版本升级的目标基线文档 `tasks/uni-pkg-version-target-baseline.md`。

### 脚本行为

- 读取 `doc/package-versions.md` 的依赖明细，识别每个包在当前工作区已存在的最高版本。
- 默认读取 `tasks/task-5-uni-pkg-version.md` 中“不进行改造的工程”段落，自动排除不在本轮范围内的仓库。
- 输出字段至少包含 `Package Id`、`Current Versions`、`Target Version`、`Source Repositories`、`In Scope`、`Strategy`、`Exception Reason`。
- 当前策略会给出 `Unified upgrade`、`Keep divergence`、`Recommend removal` 三类初始结论。
- 输出 Markdown，适合作为后续人工校正和批次推进的基线。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `PackageVersionsPath` | 输入的包版本文档路径。 | `doc\package-versions.md` |
| `TaskPath` | task-5 文档路径，用于读取排除仓库。 | `tasks\task-5-uni-pkg-version.md` |
| `OutputPath` | 输出 Markdown 文件路径。 | `tasks\uni-pkg-version-target-baseline.md` |
| `ExcludedRepositories` | 额外排除的仓库列表。 | 空 |

### 示例

```powershell
.\scripts\export-package-target-baseline.ps1
```

```powershell
.\scripts\export-package-target-baseline.ps1 -RootPath D:\SLB\Prism\PA -OutputPath .\tasks\uni-pkg-version-target-baseline.md
```

```powershell
.\scripts\export-package-target-baseline.ps1 -ExcludedRepositories Rhapsody.Service.StreamSampling,Rhapsody.Service.ActorDirector
```

## find-package-version-conflicts.ps1

`find-package-version-conflicts.ps1` 用于从 `doc/package-versions.md` 中提取仍存在多版本并存的包，生成便于 review 的冲突列表。

### 脚本行为

- 读取 `Package Dependency Details`，仅保留同时存在多个版本的包。
- 输出字段至少包含 `Package Id`、`Versions`、`Repository Count`、`Repositories`。
- 预留 `Status`、`Classification`、`Notes` 三列，方便后续区分“计划内例外”和“待处理冲突”。
- 可选读取例外文件，将已登记的包回填到冲突报告中。
- 支持直接输出到控制台，也支持通过 `-OutputPath` 写出 Markdown 文档。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `InputPath` | 输入的包版本文档路径。 | `doc\package-versions.md` |
| `OutputPath` | 输出 Markdown 文件路径。 | 不写文件，仅输出到控制台 |
| `ExceptionPath` | 计划内例外清单路径。 | `doc\package-version-conflict-exceptions.md` |

### 示例

```powershell
.\scripts\find-package-version-conflicts.ps1
```

```powershell
.\scripts\find-package-version-conflicts.ps1 -OutputPath .\tasks\uni-pkg-version-conflicts.md
```

```powershell
.\scripts\find-package-version-conflicts.ps1 -ExceptionPath .\doc\package-version-conflict-exceptions.md
```

## extract-pipeline-package-version.ps1

`extract-pipeline-package-version.ps1` 用于从 Azure DevOps 构建标题、日志片段或其他文本输入中提取真实包版本，默认输出纯版本字符串，便于后续脚本直接消费。

### 脚本行为

- 支持从 `-Text` 直接读取输入，也支持通过 `-InputPath` 读取文本文件。
- 识别类似 `#1.0.0.15601898` 或 `1.0.0.15601898` 的四段式版本号。
- 当同一段输入中存在多个候选值时，会优先选择带 `#` 前缀、且更接近 `version`、`package`、`build`、`artifact`、`release`、`pipeline` 关键词的匹配项。
- 默认输出纯文本版本号；使用 `-AsJson` 时输出包含命中来源、行号和原始匹配文本的 JSON。
- 当没有传入有效输入，或输入里未提取到版本时，会输出错误并返回非零退出码。
- 可选通过 `-OutputPath` 将结果写入文件，写出格式为 UTF-8 无 BOM 且使用 CRLF。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `InputPath` | 输入文本文件路径。 | 空 |
| `Text` | 直接传入的构建标题、日志片段或其他文本。 | 空 |
| `OutputPath` | 输出文件路径。 | 不写文件，仅输出到控制台 |
| `AsJson` | 是否输出 JSON。 | `False` |

### 示例

```powershell
.\scripts\extract-pipeline-package-version.ps1 -Text "HydraulicsTransient package #1.0.0.15601898 published"
```

```powershell
.\scripts\extract-pipeline-package-version.ps1 -InputPath .\tasks\pipeline-build-log.txt -AsJson
```

```powershell
.\scripts\extract-pipeline-package-version.ps1 -Text "release package #1.0.0.15601898" -OutputPath .\tasks\pipeline-package-version.txt
```

## verify-package-upgrade.ps1

`verify-package-upgrade.ps1` 用于对指定仓库目录执行统一包版本升级前后的基础验证。当前版本是面向试点迁移前准备工作的框架版，不会默认扫描整个工作区。

### 脚本行为

- 必须显式传入一个或多个 `RepositoryPath`，避免误跑全部业务仓库。
- 自动识别仓库内的主入口文件，优先选择根目录或一层子目录下的 `.slnx`、`.sln`、项目文件。
- 对每个目标仓库执行 `dotnet restore` 与 `dotnet build`；当 `restore` 失败时，`build` 会标记为 `Skipped`。
- 使用 `-RunTest` 时，自动识别测试项目并执行 `dotnet test --no-restore`。
- 执行文本文件 CRLF 检查，并输出 inspected / offending 统计。
- 执行“项目包引用 / nuspec 依赖版本一致性”基础检查：对匹配项目中的 `PackageReference`、`Directory.Packages.props`、`packages.config` 与 `.nuspec` `metadata/dependencies` 做比对。
- 依赖一致性检查会输出 `Passed`、`Failed`、`Skipped`、`Reserved` 四类状态，并在 JSON 中带出逐项 `Checks` 明细。
- 当前不会比较 `.nuspec` 的 `<version>`、`.csproj` 的 `Version` / `PackageVersion`，也不会比较 `SharedAssemblyInfo.cs` 中的程序集版本。
- 默认输出对象结果；使用 `-AsJson` 时输出结构化 JSON，并支持通过 `-OutputPath` 写入文件。

### 参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RepositoryPath` | 需要验证的仓库目录或仓库内文件路径。 | 必填 |
| `RunTest` | 是否执行测试项目。 | `False` |
| `AsJson` | 是否输出 JSON。 | `False` |
| `OutputPath` | 输出结果文件路径。 | 不写文件，仅输出到控制台 |

### 示例

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient
```

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient -RunTest
```

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient -AsJson -OutputPath .\tasks\verify-hydraulics-transient.json
```
