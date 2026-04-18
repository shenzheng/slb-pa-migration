<!-- markdownlint-disable-file MD013 -->

# 任务描述

制定一个规划，指定一个工程，将这个工程下所有的包引用，都升级为最新的包，然后执行pipeline，然后发布该包。

这个规划应该包含以下流程：

1. 找到所有包引用，含外部公共包。形成dependences
2. 从./doc/package-versions.json以及./doc/shared-package-versions.json，合并出每个包的最新版latest-packages
3. 根据dependences，找到每个包的最新版。编译，执行单元测试
4. 第三步成功后，启动当前分支的pipeline

请规划出这个过程所需要的脚本，skill等相关内容。
然后给出用法。

## 执行规划（单工程：依赖 → 最新版映射 → 本地验证 → 触发 Pipeline）

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

| 文件 | 内容 | 用途 |
| --- | --- | --- |
| `doc/package-versions.json` | `packages`：对象，`"包Id": "版本"` | 全仓库扫描得到的 **公共包 + 各工程已引用版本** 的聚合；作外部包与未在 Shared feed 清单中的包的版本源 |
| `doc/shared-package-versions.json` | `packages`：数组，`packageId` / `latestVersion` | ADO **PrismService** feed 上内部包（与 Shared nuspec 对齐）的 **最新版** |

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

**推荐做法**：

1. 根据 `dependences` 与 `latest-packages` 生成 **变更计划**（仅列出将发生变化的 `PackageReference`），人工或 `-WhatIf` 审阅。
2. 写回方式二选一：  
   - **按包升级**：`dotnet add <project> package <Id> -v <Version>`（适合少量变更）；  
   - **脚本批量**：对 XML 安全的 `PackageReference` 做替换（需注意条件引用、多 TFM）。
3. 在 **该工程仓库根**（Actor 目录）执行：  
   - `dotnet restore`  
   - `dotnet build -c Release`（或与 Pipeline 一致配置）  
   - `dotnet test`（若存在测试项目；可与 `scripts/verify-package-upgrade.ps1` 对齐）

**现有资产**：

- `scripts/verify-package-upgrade.ps1 -RepositoryPath Actors\...\ -RunTest`：对指定路径做 **Restore / Build /（可选）Test / CRLF** 等检查；适合作为步骤三的 **门禁**，不负责从 JSON 自动改版本。

**已实现**：`scripts/apply-latest-packages-to-repository.ps1`  
参数：`-RepositoryPath`、`-MergedLatestPath`、`-WhatIf`；省略 `-MergedLatestPath` 时默认读取与本工程 **artifactToken** 一致的 `doc/latest-packages.<token>.merged.json`。写回前用 `-WhatIf` 预览；改完后请单独运行 `verify-package-upgrade.ps1` 做门禁。

### 步骤四：提交并触发当前分支 Pipeline（发布）

**目的**：将变更推送到远程 **当前分支**，在 ADO 上排队对应 **Definition** 的构建，由 Pipeline 执行 **nuspec / Docker / Helm** 等你方已配置的发布步骤。

**推荐做法**：

1. `git status` 确认仅含预期文件；`git push` 当前分支。
2. 用 **映射表** 解析 Pipeline：`doc/rhapsody-service-to-ado-pipeline-mapping.md` 与 `scripts/upgrade-pipeline-definitions.json`。
3. 调用 Azure DevOps CLI 排队构建，例如：  
   `az pipelines run --organization https://dev.azure.com/slb1-swt --project Prism --id <definitionId> --branch <当前分支refs格式>`  
   （分支名需与 ADO 中一致，如 `refs/heads/dapr` 或 `refs/heads/feature/...`。）

**现有资产**：

- 技能 **prism-ado-pipeline-status**：`scripts/get-upgrade-pipeline-status.ps1` — 查询 **最近一次** 构建与日志链接（用于步骤四之后 **验收**）。
- 映射与 Definition ID：见 `doc/rhapsody-service-to-ado-pipeline-mapping.md`。

**已实现**：`scripts/start-upgrade-pipeline.ps1`  
参数：`-RepositoryFolderName`（与 `upgrade-pipeline-definitions.json` 中 `pipelineName` 匹配）或 `-DefinitionId`；`-Branch` 省略时用当前 git 分支构造 `refs/heads/...`；`-DryRun` 仅打印 `az` 参数。

### 建议新增 Cursor Skill（可选）

| Skill 名（建议） | 触发场景 | 内容要点 |
| --- | --- | --- |
| `prism-single-repo-package-upgrade` | 「把某 Actor 所有包升到最新并跑 Pipeline」 | 顺序调用：刷新两份 JSON → `merge` → `apply` → `verify-package-upgrade` → `git push` → `start-upgrade-pipeline` → `get-upgrade-pipeline-status`；明确 **单工程路径** 与 **分支** 参数 |

（实现 Skill 时：描述里写明依赖 `az login`、dotnet SDK、以及 `doc` 下 JSON 的刷新频率。）

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
.\scripts\verify-package-upgrade.ps1 -RepositoryPath 'Actors\Rhapsody.Computation.ChannelProjection' -RunTest

# 5）提交推送后触发 Pipeline（需 az login、azure-devops 扩展与排队权限）
# git add ...; git commit -m "..."; git push
# .\scripts\start-upgrade-pipeline.ps1 -RepositoryFolderName 'Rhapsody.Computation.ChannelProjection' -Branch 'refs/heads/dapr'

# 6）查看运行结果
.\scripts\get-upgrade-pipeline-status.ps1 -Branch 'refs/heads/dapr'
```

### 风险与约束（规划中须遵守）

- **未在两份 JSON 中出现的包**：不得猜测版本；应列入 **Unresolved** 并人工处理或补充查询脚本。
- **内部包与公共包同名冲突**：以 `shared-package-versions.json`（ADO feed）为内部包权威来源；公共扫描文件仅作补集。
- **换行**：修改的文件保持 **CRLF**（仓库规则）；`verify-package-upgrade.ps1` 已含 CRLF 检查。
- **发布**：本地脚本 **不替代** ADO 发布权限与审批；步骤四仅 **触发** 已存在的 Pipeline。

---

**文档状态**：步骤一至四对应脚本已在 `scripts/` 落地；可选 Cursor Skill `prism-single-repo-package-upgrade` 仍未添加。
