# 引用包统一升级计划

## Summary

本计划用于指导当前分支下 `Actors`、`Shared`、`Pipeline` 相关仓库开展一次“尽可能统一引用包版本”的端到端升级，并把这套方法固化为后续可重复执行的标准流程。  
计划目标不是简单追随公网最新版本，而是以当前工作区已存在、已落地、可在本次改造范围内复用的最高版本为统一目标版本；内部包则以当前分支最新代码生成出的包版本为准，再逐层回灌到上游依赖方。

## Scope

### 本次纳入升级的工程

- `Actors`
  - `Rhapsody.Computation.ChannelProjection`
  - `Rhapsody.Computation.DepthJumpCorrection`
  - `Rhapsody.Computation.Flowback`
  - `Rhapsody.Computation.HydraulicsTransient`
  - `rhapsody.computation.killsheet`
  - `Rhapsody.Computation.OperationKpi`
  - `Rhapsody.Computation.PackOff`
  - `Rhapsody.Computation.ProceduralAdherence`
- `Actors`
  - `Rhapsody.Computation.Risk`
  - `Rhapsody.Computation.RtRheology`
  - `Rhapsody.Computation.TndBroomstick`
  - `Rhapsody.Computation.Udf`
  - `Rhapsody.Computation.WellBalanceRisks`
  - `Rhapsody.Service.DrillingKpi`
  - `Rhapsody.Service.PressureMonitoring`
- `Shared`
  - `Rhapsody.Algorithm.ChannelProjection`
  - `Rhapsody.Algorithm.DepthJumpCorrection`
  - `Rhapsody.Algorithm.Risk`
  - `Rhapsody.Algorithm.Udf`
  - `Shared.Algorithm.CementingHydraulics`
  - `Shared.Algorithm.Flowback`
  - `Shared.Algorithm.HydraulicsTransientSimulation`
  - `Shared.Algorithm.KillSheet`
  - `Shared.Algorithm.OperationKpi`
  - `Shared.Algorithm.PackOff`
  - `Shared.Algorithm.ParameterAdherence`
  - `Shared.Algorithm.PressureMonitoring`
  - `Shared.Algorithm.RtRheology`
  - `Shared.Algorithm.TnDBroomstick`
  - `Shared.Library.DrillingKpi`
  - `Shared.Library.WellBalanceRisks`

### 不纳入本次改造的工程

- `Rhapsody.Computation.CementingHydraulics`
- `Rhapsody.Library.ComputationDaprAdapter`
- `Shared.Library.Computation.Common`
- `Rhapsody.Algorithm.DataGenerator`
- `Shared.Algorithm.CoreComputation`
- `Rhapsody.Computation.CoreComputation`
- `Rhapsody.Computation.DataGenerator`
- `Rhapsody.Service.ActorDirector`
- `Rhapsody.Service.StreamSampling`

## Version Policy

### 统一原则

- 外部包统一目标版本取自当前工作区 `./doc/package-versions.md` 中“已存在的最高版本”，不是公网最新版本。
- 内部包统一目标版本取自当前分支最新代码在本地修改、通过仓库 Pipeline 后生成的最新有效包版本。
- 任何包如存在明显兼容性边界，允许登记为“保留差异版本”，但必须记录原因、影响范围和后续消除方案。
- 版本收集和升级动作均以当前分支最新代码为准，执行前先统一拉取所有相关仓库最新提交。

### 内部包当前统一目标基线

以下版本来自当前 `./doc/package-versions.md`，作为首轮升级时的内部包目标基线；执行 Shared 仓库 Pipeline 后，应以新产出的包版本替换本表中的旧版本，再供 Actor 引用。

| Package Id | 当前目标版本 | Source Repository |
| --- | --- | --- |
| `Slb.Prism.Rhapsody.Algorithm.ChannelProjection` | `2.0.0.13909616` | `Rhapsody.Algorithm.ChannelProjection` |
| `Slb.Prism.Rhapsody.Algorithm.DepthJumpCorrection` | `1.0.0.11904448` | `Rhapsody.Algorithm.DepthJumpCorrection` |
| `Slb.Prism.Rhapsody.Algorithm.Risk` | `1.0.0.14728885` | `Rhapsody.Algorithm.Risk` |
| `Slb.Prism.Rhapsody.Algorithm.Udf` | `1.0.0.14533750` | `Rhapsody.Algorithm.Udf` |
| `Slb.Prism.Shared.Algorithm.CementingHydraulics` | `1.0.0.15510346` | `Shared.Algorithm.CementingHydraulics` |
| `Slb.Prism.Shared.Algorithm.Flowback` | `1.0.0.15544531` | `Shared.Algorithm.Flowback` |
| `Slb.Prism.Shared.Algorithm.HydraulicsTransientSimulation` | `1.0.0.14727081` | `Shared.Algorithm.HydraulicsTransientSimulation` |
| `Slb.Prism.Shared.Algorithm.KillSheet` | `1.0.0.15182192` | `Shared.Algorithm.KillSheet` |
| `Slb.Prism.Shared.Algorithm.OperationKpi` | `1.0.0.15543348` | `Shared.Algorithm.OperationKpi` |
| `Slb.Prism.Shared.Algorithm.PackOff` | `1.0.0.14206116` | `Shared.Algorithm.PackOff` |
| `Slb.Prism.Shared.Algorithm.ParameterAdherence` | `1.0.0.15543587` | `Shared.Algorithm.ParameterAdherence` |
| `Slb.Prism.Shared.Algorithm.PressureMonitoring` | `1.0.0.15419246` | `Shared.Algorithm.PressureMonitoring` |
| `Slb.Prism.Shared.Algorithm.RtRheology` | `1.0.16.14030028` | `Shared.Algorithm.RtRheology` |
| `Slb.Prism.Shared.Algorithm.TnDBroomstick` | `3.4.3.15248987` | `Shared.Algorithm.TnDBroomstick` |
| `Slb.Prism.Shared.Computation.DrillingKpi` | `3.4.0.15195157` | `Shared.Library.DrillingKpi` |
| `Slb.Prism.Shared.Library.WellBalanceRisks` | `2.0.0.15405187` | `Shared.Library.WellBalanceRisks` |

### 外部包统一规则

- Dapr 相关包优先统一到当前工作区已出现的最高版本。
  当前样例：`Dapr.Actors` 目标应优先评估统一到 `1.17.5`，避免 `Rhapsody.Computation.HydraulicsTransient` 仍停留在 `1.17.0`。
- 常用基础包优先统一到当前工作区最高版本。
  当前样例：`Azure.Identity -> 1.17.1`，`Newtonsoft.Json -> 13.0.4`，`Microsoft.NET.Test.Sdk -> 18.3.0`。
- 测试包以“同类仓库统一”为主，不强求一次性把所有历史测试工程都拉齐到同一套框架；但同一批改造仓库内，应尽量统一 `Microsoft.NET.Test.Sdk`、`MSTest.TestFramework`、`MSTest.TestAdapter`、`coverlet.collector`。
- 对 .NET 10 已内置能力的兼容包，优先评估移除而不是升级，例如部分 `System.*` 包、旧版 Web API 兼容包。

## Execution Order

升级顺序必须按依赖方向推进，避免 Actor 先改、Shared 包版本尚未落库导致反复回改。

1. 信息冻结阶段
   在当前分支执行：
   `scripts/git-pull-all.ps1`
   `scripts/export-repo-to-nuget-map.ps1`
   `scripts/export-package-versions.ps1`
2. 基线确认阶段
   产出“包目标版本清单”，标记：
   `统一升级`、`保留差异`、`建议移除` 三类结论。
3. Shared 底层算法仓库阶段
   先改 `Shared` 仓库中的直接算法包与数据结构包，保证这些仓库自己先完成编译、单测、打包、发布。
4. Shared Pipeline 阶段
   逐个执行 Shared 仓库 Azure DevOps Pipeline，拿到最新产物版本号。
5. Actor 仓库阶段
   Actor 仓库把对 Shared 包的引用改为第 4 步生成的真实版本，再统一外部包版本。
6. Actor Pipeline 阶段
   执行每个 Actor 仓库的构建、镜像、nuspec 打包、Helm/部署相关 Pipeline。
7. 收尾阶段
   重新导出 `package-versions.md`，确认差异已收敛，并更新升级结果文档。

## Pipeline Rule

### Shared 包版本提取规则

- Shared 仓库完成 Pipeline 后，必须以 Pipeline 产物中的真实包版本为 Actor 引用版本，不允许继续手填旧版本。
- 对类似 `#1.0.0.15601898 • Merged PR 754424: [bjing] upgrade common layer` 的记录，版本提取结果为 `1.0.0.15601898`。
- 版本提取应来自稳定来源之一：
  - Azure DevOps Build 标题或摘要
  - 发布到内部 NuGet Feed 的包版本
  - Pipeline 产出的 `.nuspec` / 构建变量
- 同一仓库若主包与 IntegrationTests 包版本不一致，应分别记录，不做想当然推断。

### Actor 回灌规则

- Actor 改造提交前，所有内部 `PackageReference` 必须引用 Shared Pipeline 已发布的真实版本。
- Actor 的 `.nuspec`、`IntegrationTests.nuspec`、工程文件中的版本号必须同步更新，避免编译引用与发布引用不一致。

## Upgrade Batches

为降低风险，本次建议按“共享依赖相近、参考样例充足、影响面从小到大”的顺序分 4 批执行。

### 批次 0：基线与工具准备

- 更新 `doc/package-versions.md`
- 生成包目标版本清单
- 准备自动化脚本
- 先不改业务代码，只确认版本策略与例外名单

### 批次 1：已有完成样例邻近仓库

- `Shared.Algorithm.PressureMonitoring` + `Rhapsody.Service.PressureMonitoring`
- `Shared.Library.DrillingKpi` + `Rhapsody.Service.DrillingKpi`
- `Rhapsody.Algorithm.ChannelProjection` + `Rhapsody.Computation.ChannelProjection`

目标：
- 利用 `DrillingKpi` 已改造完成的经验验证统一升级流程可跑通。
- 固化测试包、日志包、Dapr 包、打包文件的统一改法。

### 批次 2：单算法 Actor 成对改造

- `Shared.Algorithm.CementingHydraulics` + `Rhapsody.Computation.CementingHydraulics`
- `Shared.Algorithm.Flowback` + `Rhapsody.Computation.Flowback`
- `Shared.Algorithm.KillSheet` + `rhapsody.computation.killsheet`
- `Shared.Algorithm.OperationKpi` + `Rhapsody.Computation.OperationKpi`
- `Shared.Algorithm.PackOff` + `Rhapsody.Computation.PackOff`
- `Shared.Algorithm.ParameterAdherence` + `Rhapsody.Computation.ProceduralAdherence`

目标：
- 覆盖常见 Shared/Actor 一对一依赖模式。
- 验证内部包版本回灌和 IntegrationTests 打包联动。

### 批次 3：差异性较高仓库

- `Rhapsody.Algorithm.DepthJumpCorrection` + `Rhapsody.Computation.DepthJumpCorrection`
- `Rhapsody.Algorithm.Risk` + `Rhapsody.Computation.Risk`
- `Rhapsody.Algorithm.Udf` + `Rhapsody.Computation.Udf`
- `Shared.Algorithm.RtRheology` + `Rhapsody.Computation.RtRheology`
- `Shared.Algorithm.TnDBroomstick` + `Rhapsody.Computation.TndBroomstick`
- `Shared.Library.WellBalanceRisks` + `Rhapsody.Computation.WellBalanceRisks`

目标：
- 处理历史版本跨度较大、测试框架较旧或包差异较多的仓库。
- 清理保留差异项并建立例外模板。

### 批次 4：高风险链路专项

- `Shared.Algorithm.HydraulicsTransientSimulation` + `Rhapsody.Computation.HydraulicsTransient`

目标：
- 单独处理 `HydraulicsTransient`，因为其同时涉及 Actor、Contract、Dapr.Actors 版本不一致、参考仓库映射和调用链复杂度更高。
- 以专项方式验证 Shared 包升级、Actor 引用回灌、Contract 打包、部署链路和日志配置。

## Per-Repo Workflow

每个仓库执行时采用同一模板：

1. 拉取当前分支最新代码。
2. 记录仓库现状：
   工程文件、`Directory.Build.props`、`Directory.Packages.props`、`packages.config`、`.nuspec`、`appsettings.json`。
3. 套用包目标版本清单。
4. 编译并运行仓库内单元测试。
5. 执行仓库 Pipeline，记录新包版本。
6. 若是 Shared 仓库，则更新依赖它的 Actor 仓库引用版本。
7. 若是 Actor 仓库，则额外验证 IntegrationTests、Docker、Helm、部署模板。
8. 将结果回写到升级跟踪表。

## Verification

### 仓库级验证

- `dotnet restore` 成功
- `dotnet build` 成功
- 仓库现有单元测试全部通过
- `.nuspec` 与工程引用版本一致
- `appsettings.json` 的 `LoggerSetup:EnricherConfiguration:Properties:ProviderName` 与服务名一致
- 文本文件换行为 CRLF

### 批次级验证

- 同一批次仓库完成后重新执行 `scripts/export-package-versions.ps1`
- 目标包不再出现无计划的多版本并存
- 保留差异包均有记录和原因
- 关键 Actor 的 IntegrationTests 包能够成功生成

### 端到端验证

- Shared Pipeline 成功并可获取真实包版本
- Actor Pipeline 成功并完成 nuspec 打包
- Docker 构建通过
- Helm Chart 渲染或打包通过
- 至少选择 1 个代表性 Actor 做集成验证，确认服务启动、日志输出、依赖注入和 Actor 激活正常

## Automation

现有脚本可直接纳入流程：

- `scripts/git-pull-all.ps1`
- `scripts/export-package-versions.ps1`
- `scripts/export-repo-to-nuget-map.ps1`
- `scripts/normalize-crlf.ps1`

建议补充以下脚本，以减少人工操作并让计划可复用：

- `scripts/export-package-target-baseline.ps1`
  - 从 `doc/package-versions.md` 生成“每个包的当前统一目标版本”清单
  - 支持排除本次不在范围内的仓库
- `scripts/find-package-version-conflicts.ps1`
  - 输出仍存在多版本并存的包及涉及仓库
- `scripts/update-package-references.ps1`
  - 批量修改 `.csproj`、`Directory.Packages.props`、`packages.config` 中的包版本
- `scripts/extract-pipeline-package-version.ps1`
  - 从 Azure DevOps 构建标题、日志或 Feed 中提取真实包版本
- `scripts/update-actor-internal-package-refs.ps1`
  - 把 Shared 新产出的包版本批量回写到 Actor 仓库
- `scripts/verify-package-upgrade.ps1`
  - 聚合 restore、build、test、nuspec/version consistency、CRLF 检查

## Script-First Roadmap

本任务建议先补齐脚本与说明文档，再开始真正的仓库迁移。原因是这次工作跨多个仓库、要重复执行、还要串联 Pipeline；如果没有自动化基线，后续每个仓库都会重复人工判断、重复改同类文件，也不利于把每一步控制在可独立提交的范围内。

### 阶段 A：先补工具链

#### Step A1：生成统一目标版本基线脚本

目标：
- 新增 `scripts/export-package-target-baseline.ps1`
- 从 `doc/package-versions.md` 产出 `tasks/uni-pkg-version-target-baseline.md`
- 支持排除“不纳入本次改造的工程”

验证：
- 脚本可运行
- 生成的 Markdown 表格结构稳定
- 能正确选出当前工作区已存在的最高版本

README / 文档修改：
- 更新 `README.md`
- 更新 `doc/scripts.md`
- 说明脚本用途、参数、示例、输出文件

建议 commit 范围：
- 仅包含新脚本 + `README.md` + `doc/scripts.md` + 新生成的基线文档模板

#### Step A2：生成版本冲突报告脚本

目标：
- 新增 `scripts/find-package-version-conflicts.ps1`
- 从 `doc/package-versions.md` 产出“哪些包仍有多版本并存”的报告

验证：
- 至少能列出包名、出现版本、涉及仓库数量
- 能区分“计划内保留差异”和“未处理冲突”

README / 文档修改：
- 更新 `README.md`
- 更新 `doc/scripts.md`

建议 commit 范围：
- 仅包含冲突分析脚本与对应文档更新

#### Step A3：批量更新包引用脚本

目标：
- 新增 `scripts/update-package-references.ps1`
- 支持修改：
  - `.csproj`
  - `Directory.Packages.props`
  - `packages.config`
- 输入来源为 `tasks/uni-pkg-version-target-baseline.md` 或中间配置文件

验证：
- 对样例仓库试跑后，仅修改目标包版本，不误改其他 XML 节点
- 幂等执行，重复运行不会制造无效 diff

README / 文档修改：
- 更新 `README.md`
- 更新 `doc/scripts.md`
- 明确建议先 dry-run，再真正写入

建议 commit 范围：
- 仅包含批量改包脚本与文档更新

#### Step A4：提取 Pipeline 真实包版本脚本

目标：
- 新增 `scripts/extract-pipeline-package-version.ps1`
- 能从 Azure DevOps 输出中提取真实包版本，如 `#1.0.0.15601898`

验证：
- 对至少 2 个实际样例验证提取正确
- 输出格式稳定，便于后续脚本消费

README / 文档修改：
- 更新 `README.md`
- 更新 `doc/scripts.md`

建议 commit 范围：
- 仅包含版本提取脚本与文档更新

#### Step A5：Actor 内部包回灌脚本

目标：
- 新增 `scripts/update-actor-internal-package-refs.ps1`
- 根据 Shared 最新真实包版本，批量更新 Actor 仓库内部包引用

验证：
- 至少用 1 个 Shared/Actor 对验证
- 只更新内部包，不改外部包

README / 文档修改：
- 更新 `README.md`
- 更新 `doc/scripts.md`

建议 commit 范围：
- 仅包含回灌脚本与文档更新

#### Step A6：统一验证脚本

目标：
- 新增 `scripts/verify-package-upgrade.ps1`
- 聚合：
  - `dotnet restore`
  - `dotnet build`
  - 测试执行
  - `.nuspec`/工程版本一致性检查
  - CRLF 检查

验证：
- 对至少 1 个 Shared 仓库、1 个 Actor 仓库验证输出
- 失败时能定位到仓库和检查项

README / 文档修改：
- 更新 `README.md`
- 更新 `doc/scripts.md`

建议 commit 范围：
- 仅包含验证脚本与文档更新

### 阶段 B：用脚本生成执行基线

#### Step B1：生成目标版本基线文档

目标：
- 运行 `export-package-target-baseline.ps1`
- 生成并人工校正 `tasks/uni-pkg-version-target-baseline.md`

验证：
- 每个目标包都标明：
  - 当前版本
  - 目标版本
  - 范围
  - 处理策略
  - 是否例外

README / 文档修改：
- 无需改 `README.md`

建议 commit 范围：
- 仅包含 `tasks/uni-pkg-version-target-baseline.md`

#### Step B2：生成升级跟踪表

目标：
- 新建 `tasks/uni-pkg-version-upgrade-tracker.md`
- 按批次预填所有仓库、状态列、验证列、Pipeline 列

验证：
- 能一眼看出：
  - 当前批次
  - 是否已改包
  - 是否已 build/test
  - Shared 是否已出新包
  - Actor 是否已回灌

README / 文档修改：
- 无需改 `README.md`

建议 commit 范围：
- 仅包含 `tasks/uni-pkg-version-upgrade-tracker.md`

## Migration Roadmap

工具链完成后，再进入仓库迁移。迁移时必须保证“一个 commit 只解决一个清晰问题”，避免把脚本、版本策略、Shared 升级、Actor 回灌、Pipeline 跟踪混在同一次提交里。

### 阶段 C：试点迁移

#### Step C1：试点 Shared 仓库升级

建议起点：
- `Shared.Library.DrillingKpi`
  或
- `Shared.Algorithm.PressureMonitoring`

单次 commit 推荐粒度：
- 只改一个 Shared 仓库内的包版本与必要的编译适配
- 如需补测试代码或小范围兼容修复，可与该仓库同 commit
- 不同时改 Actor

验证：
- 该仓库 `restore/build/test` 通过

#### Step C2：试点 Shared Pipeline 结果落表

目标：
- 执行试点 Shared 仓库 Pipeline
- 提取真实包版本
- 更新 `target-baseline` 与 `upgrade-tracker`

建议 commit 范围：
- 仅更新跟踪文档

#### Step C3：试点 Actor 回灌

建议起点：
- `Rhapsody.Service.DrillingKpi`
  或
- `Rhapsody.Service.PressureMonitoring`

单次 commit 推荐粒度：
- 只改一个 Actor 仓库
- 包括内部包版本回灌、外部包统一、`.nuspec` 同步、`appsettings.json` 的 `ProviderName` 校验

验证：
- `restore/build/test`
- IntegrationTests 包生成

### 阶段 D：按批次推广迁移

后续批次按本计划的 `Upgrade Batches` 执行，但每个仓库都拆成以下可提交步骤。

#### 每个 Shared 仓库的提交拆分

1. `commit 1`
   只做包版本升级和必要的项目文件改动
2. `commit 2`
   只做因升级导致的代码兼容修复和测试修复
3. `commit 3`
   只更新升级跟踪文档，记录本仓库验证结果和 Pipeline 版本

说明：
- 如果 `commit 1` 后即可通过验证，可以省略 `commit 2`
- 不要把多个 Shared 仓库混在同一个 commit

#### 每个 Actor 仓库的提交拆分

1. `commit 1`
   只回灌内部包版本并统一外部包版本
2. `commit 2`
   只做 `.nuspec`、IntegrationTests、Docker、Helm、配置文件同步
3. `commit 3`
   只做兼容性修复、测试修复
4. `commit 4`
   只更新升级跟踪文档，记录 Shared 版本来源、Actor 验证结果、Pipeline 结果

说明：
- 如果仓库改动较小，可将 `commit 2` 与 `commit 3` 合并
- 但“代码迁移”和“跟踪文档更新”仍建议分开提交

## Commit Strategy

为了保证每一步都可审查、可回滚、可复用，建议统一采用以下提交策略。

### 脚本阶段提交策略

- 一个脚本一个 commit
- 该脚本对应的 `README.md`、`doc/scripts.md` 说明，与脚本放在同一个 commit
- 若脚本会生成样例输出文件，样例输出可以与脚本同 commit

### 仓库迁移阶段提交策略

- 一个仓库至少一个 commit，最好 2 到 4 个 commit
- Shared 和 Actor 不放在同一 commit
- 同一 commit 不跨多个业务仓库，除非只是更新总览文档

### 文档阶段提交策略

- `target-baseline` 的调整单独 commit
- `upgrade-tracker` 的阶段性状态更新单独 commit
- 如果只是同步 Pipeline 产物版本，优先只改跟踪文档，不夹带代码修改

## Deliverables

执行本计划时，建议同步维护以下产物：

- `doc/package-versions.md`
- `doc/actors-shared-repo-to-nuget.md`
- `tasks/uni-pkg-version-plan.md`
- `tasks/uni-pkg-version-target-baseline.md`
- `tasks/uni-pkg-version-upgrade-tracker.md`

其中：

- `target-baseline` 记录每个包的目标版本、是否例外、例外原因。
- `upgrade-tracker` 记录每个仓库的升级状态、Pipeline 结果、产物版本、验证结果。

## Acceptance

- 计划明确了范围、排除项、版本选择原则、执行顺序、批次划分和验证机制。
- 内部包已经定义了“先改 Shared、再跑 Pipeline、再回灌 Actor”的闭环规则。
- 明确要求从 Shared Pipeline 结果中提取真实版本号供 Actor 引用。
- 对未来重复执行场景，已经给出脚本化方向和固定交付物。
- 升级过程覆盖了代码、测试、打包、Docker、Helm、Pipeline，而不是只覆盖工程文件改包版本。

## Assumptions

- 本文档是升级计划，不是最终升级结果。
- `./doc/package-versions.md` 为当前分支下最新扫描结果，后续每个批次结束后都需要重新生成。
- 个别外部包可能因目标框架、第三方库兼容性或历史测试工程限制暂不统一，此类情况需进入例外清单。
- 后续若引入集中版本管理，可优先考虑在每个仓库内部使用 `Directory.Packages.props`，但本计划不要求一次性跨所有仓库强推统一实现方式。
