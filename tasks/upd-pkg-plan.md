# 执行规划

## 单工程：依赖 → 最新版映射 → 本地验证 → 触发 Pipeline

**范围约定**：一次只选定 **一个** 仓库根下的 Actor/Service 目录（例如 `Actors\Rhapsody.Computation.ChannelProjection`）。目标是将该目录内所有 `PackageReference`（含直接引用；可选含传递依赖报告）对齐到「已知最新版」集合，本地 `restore`/`build`/（可选）`test` 通过后，再在 ADO 上排队 **当前 Git 分支** 的 CI/CD，由 Pipeline 完成 **打包与发布**（与手改 csproj 后推分支再由 ADO 发布一致）。

### 开始前：与远端同步

在改依赖、写回 `csproj`、刷新或提交 `doc/` 下合并表之前，**先拉取远端最新提交**，避免在过时基线上改版本或产生难合并的冲突：

- **PA 聚合仓库根**：执行 `git pull`（或 `git pull --rebase`）；若有未提交本地改动，请先 `git stash`、提交到临时分支，或先处理完再拉取。
- **若选定工程为 git submodule**（多数 `Actors\...` 为独立仓库）：进入该子模块目录，检出团队约定分支（多为 `dapr`），再执行 `git pull origin <branch>`；也可在仓库根先 `git submodule update --init --recursive`，再进入子模块目录拉取。**签入顺序**：通常先在**子模块仓库** `commit` / `push`，再在 PA 根目录更新子模块指针（`git add Actors\...`）并 `commit` / `push`。

### 步骤一：依赖清单 `dependences`

**目的**：列出该工程下出现的所有包 ID 及当前声明版本（含公共 NuGet 与内部包）。

**推荐做法**（精确到选定目录）：

1. 在选定目录下枚举 `*.csproj`（排除 `bin`/`obj`）。
2. 对每个项目执行：  
   `dotnet list "<path>\Project.csproj" package --format json`  
   如需观察传递依赖：`--include-transitive`（体积大，仅排障时用）。
3. 将结果合并为一个 JSON 数组或按 `packageId` 去重，得到 **`dependences`**（可与仓库约定文件名 `doc/dependences.<工程名>.json`）。

**现有资产**：

- `scripts/export-package-versions.ps1`：按 `ProjectGroups`（如 `Actors`）**整组**扫描 csproj / packages.config，输出 `doc/package-versions.json` 的全局视图；**不替代**单工程 `dotnet list`，但可用于对照「仓库内别处用到的版本」。
- 若仅需快速人工查看：在工程目录对入口 `.sln` 或主 `.csproj` 执行 `dotnet list package`。

**已实现**：`scripts/get-project-package-dependencies.ps1`  
参数：`-RepositoryPath Actors\Rhapsody.Computation.ChannelProjection`；默认输出 `doc/dependences.<artifactToken>.json`（**artifactToken** 由**整条**相对路径生成，例如 `Actors__Rhapsody.Computation.ChannelProjection`，避免仅按末级目录名并发冲突）；可加 `-IncludeTransitive`。

### 步骤二：合并 `latest-packages`

**目的**：为每个包 ID 解析一个 **目标版本** 字符串，来源统一为两份已生成文件。

**输入**：

| 文件                               | 内容                                            | 用途                                                                                                 |
| ---------------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `doc/package-versions.json`        | `packages`：对象，`"包Id": "版本"`              | 全仓库扫描得到的 **公共包 + 各工程已引用版本** 的聚合；作外部包与未在 Shared feed 清单中的包的版本源 |
| `doc/shared-package-versions.json` | `packages`：数组，`packageId` / `latestVersion` | ADO **PrismService** feed 上内部包（与 Shared nuspec 对齐）的 **最新版**                             |

**合并规则（建议）**：

1. 将 `package-versions.json` 的 `packages` 读成字典 **D1**。
2. 将 `shared-package-versions.json` 的每项转为字典 **D2**（`packageId` → `latestVersion`，跳过 `error` 非空的项）。
3. **并集** `Keys = D1.Keys ∪ D2.Keys`。
4. **解析顺序**：若包 ID 在 **D2** 中且 `latestVersion` 有效，则 **优先采用 D2**（内部 feed 最新）；否则采用 **D1**；若均不存在，标记为 **Unresolved**（不自动升级，避免静默写错版本）。

输出 **`latest-packages`**：未指定 `-RepositoryPath` 时默认 `doc/latest-packages.merged.json`（**全局**合并表，并发写同一文件时用原子替换）；指定 `-RepositoryPath` 时默认 `doc/latest-packages.<artifactToken>.merged.json`，与 dependences 使用同一套 **artifactToken** 规则。JSON 结构为 `{ "mergedAt", "sources", "packageCount", "packages", 可选 "repositoryRelativePath", "artifactToken" }`。工程内引用但不在合并表中的包，由 **`apply-latest-packages-to-repository.ps1`** 在控制台列出（不自动改版本）。

**现有资产**：

- 刷新 `doc/shared-package-versions.json`：技能 **prism-shared-package-latest-versions**（`scripts/get-shared-package-latest-versions.ps1`，需 `az login` + `azure-devops` 扩展）。
- 刷新 `doc/package-versions.json`：`scripts/export-package-versions.ps1`（可选 `-ProjectGroups` 缩小范围，仍为组级扫描）。

**已实现**：`scripts/merge-latest-package-versions.ps1`  
可选参数：`-PackageVersionsPath`、`-SharedPackageVersionsPath`、`-RepositoryPath`、`-OutPath`。共用令牌逻辑见 `scripts/package-upgrade-artifact-naming.ps1`。

### 步骤三：写回版本、编译与单元测试

**目的**：只改选定工程下的项目文件（及必要时 `Directory.Packages.props`），使每个 `PackageReference` 的 `Version` 等于 `latest-packages` 中解析到的版本，然后本地验证。

**不修改 TFM**：包升级流程**不**更改任何 `.csproj` 中的 **`TargetFramework` / `TargetFrameworks`**。若合并表或 `apply-latest-packages-to-repository.ps1` 写回的测试相关包版本与当前测试 TFM 不兼容（例如测试 TFM 低于 **`net8.0`** 时不应使用 `Microsoft.NET.Test.Sdk` 18.x / MSTest 4.x），应**按下方「特例」手工钉死测试包版本**，不得通过把测试项目改为 `net8.0` 等方式规避。

**特例（`net5.0`）**：当测试项目的 `TargetFramework` **低于 `net8.0`**（含 **`net5.0`**、**`net6.0`**、**`net7.0`** 等）时，测试相关包**一律采用与 `net5.0` 相同的**下列版本（**不**因当前 TFM 是 `net6.0` 等而改用合并表中的高版本测试栈）：

```text
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.13.0" />
<PackageReference Include="MSTest.TestAdapter" Version="3.11.1" />
<PackageReference Include="MSTest.TestFramework" Version="3.11.1" />
<PackageReference Include="coverlet.collector" Version="8.0.1">
...
</PackageReference>
```

凡测试 TFM **低于 `net8.0`**，均按上表与 **`net5.0`** 特例对齐；**不因包升级而修改**测试项目 `TargetFramework`。

**推荐做法**：

1. 根据 `dependences` 与 `latest-packages` 生成 **变更计划**（仅列出将发生变化的 `PackageReference`），人工或 `-WhatIf` 审阅。
2. 写回方式二选一：  
   - **按包升级**：`dotnet add <project> package <Id> -v <Version>`（适合少量变更）；  
   - **脚本批量**：对 XML 安全的 `PackageReference` 做替换（需注意条件引用、多 TFM）。
3. 在 **该工程仓库根**（Actor 目录）执行：  
   - `dotnet restore`  
   - `dotnet build -c Release`（或与 Pipeline 一致配置）  
   - `dotnet test`（若存在测试项目；可与 `scripts/verify-package-upgrade.ps1` 对齐）  
   - **打包验证**：对含 `.nuspec` 或需在 CI 中打 NuGet 包的 Shared 类库，建议执行 `.\scripts\verify-package-upgrade.ps1 -RepositoryPath '...' -RunTest -RunPack`（`-RunPack` 会用 **Release** 做 build/test/pack，并执行 `dotnet pack` 做烟雾验证）。

**现有资产**：

- `scripts/verify-package-upgrade.ps1 -RepositoryPath Actors\...\ -RunTest [-RunPack]`：对指定路径做 **Restore / Build /（可选）Test /（可选）Pack / CRLF** 等检查；**仅在 restore 与 build 成功后才跑测试**，避免还原失败时仍 `dotnet test --no-restore` 造成「无有效单测」的假象。适合作为步骤三的 **门禁**，不负责从 JSON 自动改版本。

**已实现**：`scripts/apply-latest-packages-to-repository.ps1`  
参数：`-RepositoryPath`、`-MergedLatestPath`、`-WhatIf`；省略 `-MergedLatestPath` 时默认读取与本工程 **artifactToken** 一致的 `doc/latest-packages.<token>.merged.json`。写回前用 `-WhatIf` 预览；改完后请单独运行 `verify-package-upgrade.ps1` 做门禁。

### 推荐校验清单（步骤三门禁）

`apply-latest-packages-to-repository.ps1` 写回后，建议按下表自检（顺序有意义）：

| 序号 | 校验项 | 说明 |
| --- | --- | --- |
| 1 | 私有源可还原 | 本机对 Azure Artifacts 等源执行 `dotnet restore` 无 `NU1301` / `401`。否则 `get-project-package-dependencies.ps1`（依赖 `dotnet list package`）无法可靠生成 `dependences`，应先解决认证再重跑步骤一。 |
| 2 | 门禁脚本 | 在 PA 仓库根执行 `.\scripts\verify-package-upgrade.ps1 -RepositoryPath '<相对路径>' -RunTest`；含 `.nuspec` 或需在 CI 产出的 Shared 类库建议加 **`-RunPack`**。期望 **Restore**、**Build** 为 Passed；**仅在二者均成功后才执行测试**，避免还原失败时仍 `dotnet test --no-restore` 造成假通过。失败时进程 **退出码为 1**。详见 `doc/scripts.md`。 |
| 3 | 测试包与 TFM（不升 TFM） | 测试 TFM **低于 `net8.0`** 时，测试相关包须按步骤三 **「特例（`net5.0`）」** 表钉死（与 **`net5.0`** 相同版本），**不要**仅信任合并表升到 MSTest 4.x / `Microsoft.NET.Test.Sdk` 18.x；**不得**为兼容新测试栈而修改测试项目的 `TargetFramework`。 |
| 4 | nuspec 与主工程 | 若使用 `verify-package-upgrade.ps1` 的依赖一致性检查：主工程每个直接 `PackageReference` 应在同名逻辑对应的 `.nuspec` `dependencies` 中有 **相同包 ID 与版本**（或团队明确约定例外并文档化）。 |
| 5 | 公共包与主库 TFM | 合并写回后若编译失败，核对是否误升了与主库 **TargetFramework** 不匹配的公共包（例如 **netstandard2.0** 上的 `System.Runtime.Caching`）；必要时在 csproj **钉死** 兼容版本并同步 nuspec。**不**通过修改主库 TFM 来「适配」某公共包版本。 |
| 6 | CRLF | 修改的文件保持 **CRLF**；可用 `scripts/normalize-crlf.ps1` 纠偏。 |

### 注意项（易错点，近期升级复盘）

- **步骤一与私有源**：`dotnet list package` / `get-project-package-dependencies.ps1` 需要能完成依赖解析；仅当凭据有效时，清单中的 resolved 版本才有意义。
- **内部包升级与传递依赖**：提升 `Slb.Prism.Shared.Library.ComputationEngine` 等内部包会改变 **传递依赖** 与所需 NuGet 源；必须在可访问相关 feed 的环境中做完整 **restore → build → test**。
- **`doc/package-versions.json` 的定位**：其公共包版本来自**全仓库**聚合，**不保证**对每个工程的 TFM 都最优；自动写回后必须以本地编译与测试为准，必要时手工回退或钉版本；**不**将「改 `TargetFramework`」作为包升级手段。
- **Shared 与 Actors 同等流程**：`RepositoryPath` 可指向 `Shared\...` 或 `Actors\...`，步骤与校验相同；不要跳过 `-RunTest` / `-RunPack`（若适用）仅靠合并表「看起来最新」。

### 端到端用法（规划落地后的命令流）

以下以 `Actors\Rhapsody.Computation.ChannelProjection` 为例。

```powershell
# 0）仓库根；并与远端同步（见上文「开始前：与远端同步」）
Set-Location D:\SLB\Prism\PA
git pull
# 若目标为 submodule，例如：cd Actors\Rhapsody.Computation.ChannelProjection; git checkout dapr; git pull

# 1）刷新「最新版」数据源（可先跳过若文件已新）
.\scripts\export-package-versions.ps1
.\scripts\get-shared-package-latest-versions.ps1

# 2）单工程依赖
.\scripts\get-project-package-dependencies.ps1 -RepositoryPath 'Actors\Rhapsody.Computation.ChannelProjection'

# 3）合并 latest-packages（按工程隔离输出，便于并发）
.\scripts\merge-latest-package-versions.ps1 -RepositoryPath 'Actors\Rhapsody.Computation.ChannelProjection'

# 4）预览写回，再执行并跑验证（默认读取同 token 的 merged 文件）
.\scripts\apply-latest-packages-to-repository.ps1 -RepositoryPath 'Actors\Rhapsody.Computation.ChannelProjection' -WhatIf
.\scripts\apply-latest-packages-to-repository.ps1 -RepositoryPath 'Actors\Rhapsody.Computation.ChannelProjection'
.\scripts\verify-package-upgrade.ps1 -RepositoryPath 'Actors\Rhapsody.Computation.ChannelProjection' -RunTest -RunPack

# 5）提交推送后触发 Pipeline（需 az login、azure-devops 扩展与排队权限）
# git add ...; git commit -m "..."; git push
# .\scripts\start-upgrade-pipeline.ps1 -RepositoryFolderName 'Rhapsody.Computation.ChannelProjection' -Branch 'refs/heads/dapr'

# 6）查看运行结果
.\scripts\get-upgrade-pipeline-status.ps1 -Branch 'refs/heads/dapr'
```

### 风险与约束（规划中须遵守）

- **未在两份 JSON 中出现的包**：不得猜测版本；应列入 **Unresolved** 并人工处理或补充查询脚本。
- **内部包与公共包同名冲突**：以 `shared-package-versions.json`（ADO feed）为内部包权威来源；公共扫描文件仅作补集。
- **换行**：修改的文件保持 **CRLF**（仓库规则）；`verify-package-upgrade.ps1` 已含 CRLF 检查；纠偏见「推荐校验清单」第 6 项。
- **合并表与 TFM / 公共包**：`doc/package-versions.json` 中的版本来自全仓库聚合，可能与某一工程的 TFM 不匹配；合并写回后必须以 **restore/build/test** 为准，必要时 **钉死** 版本；**不修改**工程既有 `TargetFramework`；详见「推荐校验清单」第 3、5 项与「注意项」。
- **测试 TFM 低于 `net8.0`**：测试相关 `PackageReference` 一律按步骤三 **「特例（`net5.0`）」** 表处理（与 **`net5.0`** 相同版本），**不**随合并表升级测试栈。
- **门禁失败可观测性**：`verify-package-upgrade.ps1` 任一检查失败时进程 **退出码为 1**（便于 CI 与脚本编排）。
- **发布**：本地脚本 **不替代** ADO 发布权限与审批；步骤四仅 **触发** 已存在的 Pipeline。

---

**文档状态**：步骤一至四对应脚本已在 `scripts/` 落地；可选 Cursor Skill `prism-single-repo-package-upgrade` 仍未添加。
