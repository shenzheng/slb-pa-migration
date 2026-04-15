# Scripts 使用说明

## 概述

本文档说明 `scripts` 目录下各个 PowerShell 脚本及配套数据文件的用途和用法。

### 脚本与数据文件一览

下文各节标题与下列文件名对应；在编辑器中可用搜索或大纲跳转。

**文档内导航（GitHub / Azure DevOps）**：下表「文件」列已链接至对应二级标题（`## …`）。锚点规则与 [GitHub 章节链接说明](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#section-links) 一致：字母小写、空格为 `-`、**其余标点（含文件名中的 `.`）会从片段中删除**。Azure DevOps（Wiki、Repos 中 Markdown 预览等）通常生成兼容的片段；若与贵组织渲染器不一致，可将鼠标悬停在已渲染页面的标题上查看实际锚点，或使用页面自带目录 / 全文搜索脚本名。

| 文件 | 说明 |
| --- | --- |
| [convert-nested-repos-to-submodules.ps1](#convert-nested-repos-to-submodulesps1) | 将 `Actors` / `Pipeline` / `Shared` 下嵌套克隆注册为父仓库的 git submodule |
| [export-package-target-baseline.ps1](#export-package-target-baselineps1) | 基于 `package-versions.md` 生成统一包版本升级目标基线文档 |
| [export-package-versions.ps1](#export-package-versionsps1) | 扫描工程依赖并生成 NuGet 包版本与依赖明细 Markdown |
| [export-repo-to-nuget-map.ps1](#export-repo-to-nuget-mapps1) | 扫描 `.nuspec` 生成仓库与 NuGet 包映射表 |
| [extract-pipeline-package-version.ps1](#extract-pipeline-package-versionps1) | 从构建标题或日志文本中提取四段式包版本号 |
| [find-package-version-conflicts.ps1](#find-package-version-conflictsps1) | 从 `package-versions.md` 提取多版本并存包，生成冲突列表 |
| [get-upgrade-pipeline-status.ps1](#get-upgrade-pipeline-statusps1) | 通过 Azure CLI 查询升级相关 ADO Pipeline 在指定分支上的最近构建状态 |
| [git-pull-all.ps1](#git-pull-allps1) | 批量对 `Actors` / `Shared`（可配置）下各仓库执行 `git pull --ff-only` |
| [normalize-crlf.ps1](#normalize-crlfps1) | 将指定目录下文本文件中的纯 LF 换行规范为 CRLF |
| [upgrade-pipeline-definitions.json](#upgrade-pipeline-definitionsjson) | `get-upgrade-pipeline-status.ps1` 使用的 Pipeline 定义列表（组织、项目、definitionId） |
| [verify-package-upgrade.ps1](#verify-package-upgradeps1) | 对指定仓库执行 restore/build（可选 test）及依赖与 CRLF 等检查 |

## convert-nested-repos-to-submodules.ps1

`convert-nested-repos-to-submodules.ps1` 用于把父仓库（PA）下 `Actors`、`Pipeline`、`Shared` 目录中**已存在的嵌套 Git 克隆**（各目录自带 `.git`）转为正式的 **git submodule**（写入 `.gitmodules` 并在父仓库索引中记录 gitlink）。

### 前置条件（convert-submodules）

- 已安装 `git`，且能访问各子仓库远端（HTTPS 或 SSH，取决于 `origin` URL）。
- 嵌套仓库**未提交的工作区改动**会在删除目录时丢失；执行前请在各子仓库中提交或 stash，或使用 `-AllowDirty`（仍会被删除，仅跳过“脏检查”）。

### 脚本行为（convert-submodules）

- 默认扫描 `Actors`、`Pipeline`、`Shared` 下一层子目录；仅处理存在 `.git` 的目录。
- 已从索引登记的 submodule 路径会 **SKIP**（通过 `git ls-files -s` 检测 mode `160000`）。
- 转换前会从 `.gitignore` 中移除 `Actors/`、`Pipeline/`、`Shared/` 以及 `Rhapsody.Computation.Flowback/`（后者无前导 `/` 时会误匹配 `Actors/.../Flowback`）。
- 删除原目录时使用重试、`attrib`、改名再删、`rd /s /q` 等，减轻 Windows 下文件占用导致的失败；失败残留时会在执行 `git submodule add` 前清理 `.git/modules` 下对应路径及 `git config submodule.<path>` 节（`Clear-StaleSubmoduleMetadata`）。
- 对每个仓库执行 `git submodule add -b <branch> <origin> <相对路径>`。若远端不存在所选分支（例如某库无 `dapr`），需手工指定分支或单独 `git submodule add`。

### 参数（convert-submodules）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 父仓库（PA）根目录。 | `scripts` 的上一级目录 |
| `ProjectGroups` | 要扫描的顶层目录名。 | `Actors`, `Pipeline`, `Shared` |
| `BranchMode` | `Each`：各子仓库当前分支；`Parent`：全部使用父仓库当前分支名（远端须存在该分支）。 | `Each` |
| `WhatIf` | 仅打印将执行的 `git submodule add` 命令，不修改磁盘与索引。 | 关闭 |
| `AllowDirty` | 跳过“工作区必须干净”的检查（仍会删除目录）。 | 关闭 |
| `Only` | 仅处理相对路径中包含该子串的仓库（用于单库补跑）。 | 空 |

### 示例（convert-submodules）

```powershell
.\scripts\convert-nested-repos-to-submodules.ps1 -WhatIf
```

```powershell
.\scripts\convert-nested-repos-to-submodules.ps1 -RootPath D:\SLB\Prism\PA
```

```powershell
.\scripts\convert-nested-repos-to-submodules.ps1 -Only "Pipeline/CD" -WhatIf
```

```powershell
.\scripts\convert-nested-repos-to-submodules.ps1 -BranchMode Parent
```

完成后请在父仓库中审阅 `git status`，并提交 `.gitmodules` 与各 submodule 的 gitlink。

## git-pull-all.ps1

`git-pull-all.ps1` 用于拉取 `Actors` 和 `Shared` 目录下各 Git 仓库当前分支的最新代码。

### 脚本行为（git-pull-all）

- 使用 `git pull --ff-only`，避免自动生成 merge commit。
- 输出实时进度、当前仓库和每个仓库的处理耗时。
- 处于 detached `HEAD` 状态或未配置上游分支的仓库会被跳过并记录。
- 只要任意仓库拉取失败，脚本会以退出码 `1` 结束。

### 参数（git-pull-all）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `ProjectGroups` | 需要扫描的顶层目录。 | `Actors`, `Shared` |

### 示例（git-pull-all）

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

### 脚本行为（normalize-crlf）

- 扫描 `.cs`、`.csproj`、`.json`、`.md`、`.ps1` 等常见文本文件扩展名。
- 自动排除 `.git`、`bin`、`obj`、`packages` 等常见生成目录或工具目录。
- 仅重写包含纯 `LF` 换行的文件。

### 参数（normalize-crlf）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 递归扫描的根目录。 | 当前目录 |

### 示例（normalize-crlf）

```powershell
.\scripts\normalize-crlf.ps1 -RootPath D:\SLB\Prism\PA
```

## export-repo-to-nuget-map.ps1

`export-repo-to-nuget-map.ps1` 用于扫描一组仓库中的 `.nuspec` 文件，并生成 repository 与 NuGet 包的映射文档。

### 脚本行为（export-repo-to-nuget-map）

- 默认扫描 `Actors`、`Shared`、`Pipeline` 三个顶层目录。
- 在每个一层仓库目录下递归查找 `.nuspec` 文件。
- 解析 `.nuspec` 的 `metadata/id` 与 `metadata/version`。
- 生成包含 `Project Group`、`Repository`、`Package Id`、`Version`、`Nuspec Path` 的 Markdown 表格。

### 参数（export-repo-to-nuget-map）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `ProjectGroups` | 需要扫描的顶层目录。 | `Actors`, `Shared`, `Pipeline` |
| `OutputPath` | 输出 Markdown 文件路径。 | `doc\repo-to-nuget-map.md` |

### 示例（export-repo-to-nuget-map）

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

### 脚本行为（export-package-versions）

- 默认扫描 `Actors`、`Shared` 两个顶层目录。
- 递归分析工程文件中的 `PackageReference`，并兼容 `packages.config`。
- 支持读取工程目录链上的 `Directory.Build.props` 与 `Directory.Packages.props`。
- 生成 `Package Version Summary` 与 `Package Dependency Details` 两部分结果。
- 自动识别 `Actors` 或 `Shared` 仓库自身产出的包，并在 `Source` 列中标记来源仓库。

### 参数（export-package-versions）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `ProjectGroups` | 需要扫描的顶层目录。 | `Actors`, `Shared` |
| `OutputPath` | 输出 Markdown 文件路径。 | `doc\package-versions.md` |

### 示例（export-package-versions）

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

### 脚本行为（export-package-target-baseline）

- 读取 `doc/package-versions.md` 的依赖明细，识别每个包在当前工作区已存在的最高版本。
- 默认读取 `tasks/task-5-uni-pkg-version.md` 中“不进行改造的工程”段落，自动排除不在本轮范围内的仓库。
- 输出字段至少包含 `Package Id`、`Current Versions`、`Target Version`、`Source Repositories`、`In Scope`、`Strategy`、`Exception Reason`。
- 当前策略会给出 `Unified upgrade`、`Keep divergence`、`Recommend removal` 三类初始结论。
- 输出 Markdown，适合作为后续人工校正和批次推进的基线。

### 参数（export-package-target-baseline）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `PackageVersionsPath` | 输入的包版本文档路径。 | `doc\package-versions.md` |
| `TaskPath` | task-5 文档路径，用于读取排除仓库。 | `tasks\task-5-uni-pkg-version.md` |
| `OutputPath` | 输出 Markdown 文件路径。 | `tasks\uni-pkg-version-target-baseline.md` |
| `ExcludedRepositories` | 额外排除的仓库列表。 | 空 |

### 示例（export-package-target-baseline）

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

### 脚本行为（find-package-version-conflicts）

- 读取 `Package Dependency Details`，仅保留同时存在多个版本的包。
- 输出字段至少包含 `Package Id`、`Versions`、`Repository Count`、`Repositories`。
- 预留 `Status`、`Classification`、`Notes` 三列，方便后续区分“计划内例外”和“待处理冲突”。
- 可选读取例外文件，将已登记的包回填到冲突报告中。
- 支持直接输出到控制台，也支持通过 `-OutputPath` 写出 Markdown 文档。

### 参数（find-package-version-conflicts）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RootPath` | 仓库根目录路径。 | `scripts` 目录的上一级目录 |
| `InputPath` | 输入的包版本文档路径。 | `doc\package-versions.md` |
| `OutputPath` | 输出 Markdown 文件路径。 | 不写文件，仅输出到控制台 |
| `ExceptionPath` | 计划内例外清单路径。 | `doc\package-version-conflict-exceptions.md` |

### 示例（find-package-version-conflicts）

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

### 脚本行为（extract-pipeline-package-version）

- 支持从 `-Text` 直接读取输入，也支持通过 `-InputPath` 读取文本文件。
- 识别类似 `#1.0.0.15601898` 或 `1.0.0.15601898` 的四段式版本号。
- 当同一段输入中存在多个候选值时，会优先选择带 `#` 前缀、且更接近 `version`、`package`、`build`、`artifact`、`release`、`pipeline` 关键词的匹配项。
- 默认输出纯文本版本号；使用 `-AsJson` 时输出包含命中来源、行号和原始匹配文本的 JSON。
- 当没有传入有效输入，或输入里未提取到版本时，会输出错误并返回非零退出码。
- 可选通过 `-OutputPath` 将结果写入文件，写出格式为 UTF-8 无 BOM 且使用 CRLF。

### 参数（extract-pipeline-package-version）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `InputPath` | 输入文本文件路径。 | 空 |
| `Text` | 直接传入的构建标题、日志片段或其他文本。 | 空 |
| `OutputPath` | 输出文件路径。 | 不写文件，仅输出到控制台 |
| `AsJson` | 是否输出 JSON。 | `False` |

### 示例（extract-pipeline-package-version）

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

### 脚本行为（verify-package-upgrade）

- 必须显式传入一个或多个 `RepositoryPath`，避免误跑全部业务仓库。
- 自动识别仓库内的主入口文件，优先选择根目录或一层子目录下的 `.slnx`、`.sln`、项目文件。
- 对每个目标仓库执行 `dotnet restore` 与 `dotnet build`；当 `restore` 失败时，`build` 会标记为 `Skipped`。
- 使用 `-RunTest` 时，自动识别测试项目并执行 `dotnet test --no-restore`。
- 执行文本文件 CRLF 检查，并输出 inspected / offending 统计。
- 执行“项目包引用 / nuspec 依赖版本一致性”基础检查：对匹配项目中的 `PackageReference`、`Directory.Packages.props`、`packages.config` 与 `.nuspec` `metadata/dependencies` 做比对。
- 依赖一致性检查会输出 `Passed`、`Failed`、`Skipped`、`Reserved` 四类状态，并在 JSON 中带出逐项 `Checks` 明细。
- 当前不会比较 `.nuspec` 的 `<version>`、`.csproj` 的 `Version` / `PackageVersion`，也不会比较 `SharedAssemblyInfo.cs` 中的程序集版本。
- 默认输出对象结果；使用 `-AsJson` 时输出结构化 JSON，并支持通过 `-OutputPath` 写入文件。

### 参数（verify-package-upgrade）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `RepositoryPath` | 需要验证的仓库目录或仓库内文件路径。 | 必填 |
| `RunTest` | 是否执行测试项目。 | `False` |
| `AsJson` | 是否输出 JSON。 | `False` |
| `OutputPath` | 输出结果文件路径。 | 不写文件，仅输出到控制台 |

### 示例（verify-package-upgrade）

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient
```

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient -RunTest
```

```powershell
.\scripts\verify-package-upgrade.ps1 -RepositoryPath .\Actors\Rhapsody.Computation.HydraulicsTransient -AsJson -OutputPath .\tasks\verify-hydraulics-transient.json
```

## get-upgrade-pipeline-status.ps1

`get-upgrade-pipeline-status.ps1` 用于查询 **Prism 升级相关** Azure DevOps Pipeline 在指定引用（分支）上的**最近一次构建**状态，并生成 Markdown 表格、JSON 或 PowerShell 对象，包含构建结果页与「最后 Stage」日志深链（需 Timeline API；可用 `-SkipTimeline` 跳过）。

### 前置条件（get-upgrade-pipeline-status）

- 已安装 **Azure CLI**（`az`），并已执行 `az login`（AAD 登录，无需 PAT）。
- 令牌通过 `az account get-access-token --resource 499b84ac-1321-4277-86b9-215fbc768055` 获取，用于调用 `dev.azure.com` REST API。

### 脚本行为（get-upgrade-pipeline-status）

- 默认读取同目录下的 `upgrade-pipeline-definitions.json`（见下文「upgrade-pipeline-definitions.json」小节），按其中 `definitionId` 逐个查询构建列表。
- 默认查询分支 `refs/heads/dapr` 上每个定义的最近一次完成构建（`$top=1`，按完成时间降序）。
- 使用 `-FallbackAnyBranch` 时，若指定分支无构建，再查询**全分支**上最近一次构建。
- 「最后 Stage」取自 Build Timeline 中 `type` 为 `Stage` 的记录中 `order` 最大者；日志链接形如 `.../_build/results?buildId=...&view=logs&t=<StageRecordId>`（若 UI 版本差异，以构建结果页为准）。
- 输出格式：`Markdown`（默认，打印到控制台或 `-OutFile`）、`Json`、`Object`。

### 参数（get-upgrade-pipeline-status）

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `Organization` | Azure DevOps 组织名。 | 从 JSON 的 `organization` 读取 |
| `Project` | 项目名称。 | 从 JSON 的 `project` 读取 |
| `DefinitionsPath` | Pipeline 定义列表 JSON 路径。 | 与脚本同目录的 `upgrade-pipeline-definitions.json` |
| `Branch` | 要筛选的源分支引用。 | `refs/heads/dapr` |
| `OutputFormat` | `Markdown`、`Json` 或 `Object`。 | `Markdown` |
| `FallbackAnyBranch` | 指定分支无构建时是否回退到全分支最近一次。 | 关闭 |
| `SkipTimeline` | 不请求 Timeline，不解析最后 Stage。 | 关闭 |
| `OutFile` | 将 Markdown 或 JSON 写入文件（UTF-8 BOM）；目录不存在时会创建。 | 不写文件 |

### 示例（get-upgrade-pipeline-status）

```powershell
.\scripts\get-upgrade-pipeline-status.ps1
```

```powershell
.\scripts\get-upgrade-pipeline-status.ps1 -Branch refs/heads/main -OutFile .\tasks\ado-pipeline-status.md
```

```powershell
.\scripts\get-upgrade-pipeline-status.ps1 -OutputFormat Json -FallbackAnyBranch -OutFile .\tasks\ado-pipeline-status.json
```

```powershell
.\scripts\get-upgrade-pipeline-status.ps1 -Organization slb1-swt -Project Prism
```

## upgrade-pipeline-definitions.json

`upgrade-pipeline-definitions.json` 是 **`get-upgrade-pipeline-status.ps1` 的配套数据文件**，与脚本位于同一目录。

### 内容说明（upgrade-pipeline-definitions）

- `organization`、`project`：Azure DevOps 组织与项目；可被脚本参数 `-Organization` / `-Project` 覆盖。
- `pipelines`：数组，每项至少包含 `definitionId`（Pipeline 定义 ID）与 `pipelineName`（展示名称）。
- 定义 ID 与 `doc/rhapsody-service-to-ado-pipeline-mapping.md` 等文档对齐，并包含参考工程（如 ActorDirector、StreamSampling、DataGenerator）等。

### 维护建议（upgrade-pipeline-definitions）

- 在 Azure DevOps 中新建或重命名 Pipeline 后，应更新本文件中的 `definitionId` / `pipelineName`，并同步文档中的映射表。
- 修改 JSON 后无需改脚本，除非 API 或查询逻辑变更。

### 示例（upgrade-pipeline-definitions）

脚本默认读取该文件；若需副本或分环境维护，可复制后使用 `-DefinitionsPath`：

```powershell
.\scripts\get-upgrade-pipeline-status.ps1 -DefinitionsPath .\scripts\upgrade-pipeline-definitions.json
```
