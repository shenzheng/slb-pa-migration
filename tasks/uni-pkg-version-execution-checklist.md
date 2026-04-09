# 引用包统一升级执行清单

## Summary

本文档是 [uni-pkg-version-plan.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-plan.md) 的落地执行版。  
目标是把“统一包版本升级”拆成一串可以顺序执行、每一步都可以单独提交的任务，方便后续按 commit 推进、审查和回滚。

## 使用方式

- 按顺序执行，不建议跳步。
- 每完成一个步骤，就完成一次本地验证。
- 每个步骤都尽量收敛到单一目的，并形成单独 commit。
- 若某一步失败，先在当前步骤内修复，不要把问题带到下一步。

## Phase 0：准备

### Step 0.1：同步当前分支最新代码

操作：
- 运行 `scripts/git-pull-all.ps1`

验证：
- 所有纳入范围仓库已拉取最新代码
- 跳过项和失败项有记录

建议 commit：
- 无

### Step 0.2：刷新当前依赖基线

操作：
- 运行 `scripts/export-repo-to-nuget-map.ps1`
- 运行 `scripts/export-package-versions.ps1`

验证：
- [actors-shared-repo-to-nuget.md](D:\SLB\Prism\PA\doc\actors-shared-repo-to-nuget.md) 已更新
- [package-versions.md](D:\SLB\Prism\PA\doc\package-versions.md) 已更新

建议 commit：
- `commit 01`
  - 仅提交基线文档刷新结果

## Phase 1：脚本建设

### Step 1.1：实现目标版本基线导出脚本

操作：
- 新增 `scripts/export-package-target-baseline.ps1`
- 输出 `tasks/uni-pkg-version-target-baseline.md`
- 更新 [README.md](D:\SLB\Prism\PA\README.md)
- 更新 [scripts.md](D:\SLB\Prism\PA\doc\scripts.md)

验证：
- 能从 `doc/package-versions.md` 选出每个包的当前最高版本
- 能排除不在本次范围内的工程
- 生成的 Markdown 结构稳定

建议 commit：
- `commit 02`
  - 仅包含该脚本、README、scripts 文档、样例输出

### Step 1.2：实现版本冲突分析脚本

操作：
- 新增 `scripts/find-package-version-conflicts.ps1`
- 更新 [README.md](D:\SLB\Prism\PA\README.md)
- 更新 [scripts.md](D:\SLB\Prism\PA\doc\scripts.md)

验证：
- 能输出仍有多版本的包
- 能列出涉及仓库或工程

建议 commit：
- `commit 03`
  - 仅包含冲突分析脚本及文档

### Step 1.3：实现批量改包脚本

操作：
- 新增 `scripts/update-package-references.ps1`
- 支持 `.csproj`、`Directory.Packages.props`、`packages.config`
- 更新 [README.md](D:\SLB\Prism\PA\README.md)
- 更新 [scripts.md](D:\SLB\Prism\PA\doc\scripts.md)

验证：
- dry-run 输出准确
- 实际写入只修改目标包版本
- 重复执行无额外噪音 diff

建议 commit：
- `commit 04`
  - 仅包含批量改包脚本及文档

### Step 1.4：实现 Pipeline 版本提取脚本

操作：
- 新增 `scripts/extract-pipeline-package-version.ps1`
- 更新 [README.md](D:\SLB\Prism\PA\README.md)
- 更新 [scripts.md](D:\SLB\Prism\PA\doc\scripts.md)

验证：
- 能从类似 `#1.0.0.15601898 • Merged PR ...` 提取 `1.0.0.15601898`
- 至少对 2 个样例验证正确

建议 commit：
- `commit 05`
  - 仅包含版本提取脚本及文档

### Step 1.5：实现 Actor 回灌脚本

操作：
- 新增 `scripts/update-actor-internal-package-refs.ps1`
- 更新 [README.md](D:\SLB\Prism\PA\README.md)
- 更新 [scripts.md](D:\SLB\Prism\PA\doc\scripts.md)

验证：
- 能按 Shared 真实版本批量回写 Actor 内部包引用
- 不误改外部包

建议 commit：
- `commit 06`
  - 仅包含回灌脚本及文档

### Step 1.6：实现统一验证脚本

操作：
- 新增 `scripts/verify-package-upgrade.ps1`
- 更新 [README.md](D:\SLB\Prism\PA\README.md)
- 更新 [scripts.md](D:\SLB\Prism\PA\doc\scripts.md)

验证：
- 能检查 `restore/build/test`
- 能检查 `.nuspec` 与工程版本一致性
- 能检查 CRLF

建议 commit：
- `commit 07`
  - 仅包含验证脚本及文档

## Phase 2：基线与跟踪文档

### Step 2.1：生成并校正目标版本基线

操作：
- 运行 `scripts/export-package-target-baseline.ps1`
- 人工补充例外项、保留差异原因、建议移除项

验证：
- 每个重点包都有目标版本
- 例外项有原因

建议 commit：
- `commit 08`
  - 仅提交 [uni-pkg-version-target-baseline.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-target-baseline.md)

### Step 2.2：建立升级跟踪表

操作：
- 新建并填写 [uni-pkg-version-upgrade-tracker.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-upgrade-tracker.md)
- 预填所有仓库、批次、状态列、验证列

验证：
- 能直接用于记录每个仓库的迁移状态和 Pipeline 状态

建议 commit：
- `commit 09`
  - 仅提交升级跟踪表

## Phase 3：试点迁移

### Step 3.1：试点 Shared 仓库版本升级

建议仓库：
- `Shared.Library.DrillingKpi`
  或
- `Shared.Algorithm.PressureMonitoring`

操作：
- 用 `update-package-references.ps1` 或手工方式统一包版本
- 修复必要的编译或测试兼容问题

验证：
- `dotnet restore`
- `dotnet build`
- 单元测试通过

建议 commit：
- `commit 10`
  - 仅提交该 Shared 仓库的版本升级与项目文件改动
- `commit 11`
  - 如需要，仅提交该 Shared 仓库的兼容性修复或测试修复

### Step 3.2：记录试点 Shared Pipeline 产物版本

操作：
- 执行试点 Shared Pipeline
- 用 `extract-pipeline-package-version.ps1` 提取真实版本
- 更新 [uni-pkg-version-target-baseline.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-target-baseline.md)
- 更新 [uni-pkg-version-upgrade-tracker.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-upgrade-tracker.md)

验证：
- Shared 真实版本已记录
- 后续 Actor 可直接引用该版本

建议 commit：
- `commit 12`
  - 仅提交基线文档与跟踪文档更新

### Step 3.3：试点 Actor 回灌与升级

建议仓库：
- `Rhapsody.Service.DrillingKpi`
  或
- `Rhapsody.Service.PressureMonitoring`

操作：
- 回灌 Shared 最新真实版本
- 统一外部包版本
- 同步 `.nuspec`、`IntegrationTests.nuspec`、必要配置文件

验证：
- `dotnet restore`
- `dotnet build`
- 测试通过
- IntegrationTests 包能生成

建议 commit：
- `commit 13`
  - 仅提交 Actor 仓库的包版本更新
- `commit 14`
  - 仅提交 `.nuspec`、IntegrationTests、配置文件同步
- `commit 15`
  - 如需要，仅提交兼容性修复或测试修复

### Step 3.4：记录试点结果

操作：
- 更新 [uni-pkg-version-upgrade-tracker.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-upgrade-tracker.md)
- 重新运行 `find-package-version-conflicts.ps1`

验证：
- 能看到试点仓库状态
- 能看到试点后差异收敛情况

建议 commit：
- `commit 16`
  - 仅提交跟踪文档更新

## Phase 4：批次推广

### Step 4.1：完成批次 1

范围：
- `Shared.Algorithm.PressureMonitoring`
- `Rhapsody.Service.PressureMonitoring`
- `Shared.Library.DrillingKpi`
- `Rhapsody.Service.DrillingKpi`
- `Rhapsody.Algorithm.ChannelProjection`
- `Rhapsody.Computation.ChannelProjection`

每个仓库的提交模式：
- 版本升级一个 commit
- 兼容修复一个 commit
- 跟踪文档一个 commit

建议 commit：
- `commit 17+`
  - 逐仓库推进，不混仓库

### Step 4.2：完成批次 2

范围：
- `Shared.Algorithm.CementingHydraulics`
- `Rhapsody.Computation.CementingHydraulics`
- `Shared.Algorithm.Flowback`
- `Rhapsody.Computation.Flowback`
- `Shared.Algorithm.KillSheet`
- `rhapsody.computation.killsheet`
- `Shared.Algorithm.OperationKpi`
- `Rhapsody.Computation.OperationKpi`
- `Shared.Algorithm.PackOff`
- `Rhapsody.Computation.PackOff`
- `Shared.Algorithm.ParameterAdherence`
- `Rhapsody.Computation.ProceduralAdherence`

建议 commit：
- 按“一个 Shared 仓库一组 commit”
- 再按“对应 Actor 仓库一组 commit”
- 最后更新文档单独 commit

### Step 4.3：完成批次 3

范围：
- `Rhapsody.Algorithm.DepthJumpCorrection`
- `Rhapsody.Computation.DepthJumpCorrection`
- `Rhapsody.Algorithm.Risk`
- `Rhapsody.Computation.Risk`
- `Rhapsody.Algorithm.Udf`
- `Rhapsody.Computation.Udf`
- `Shared.Algorithm.RtRheology`
- `Rhapsody.Computation.RtRheology`
- `Shared.Algorithm.TnDBroomstick`
- `Rhapsody.Computation.TndBroomstick`
- `Shared.Library.WellBalanceRisks`
- `Rhapsody.Computation.WellBalanceRisks`

说明：
- 这一批历史差异大，允许一个仓库拆更多 commit
- 但仍应保持“一次提交只解决一个问题”

### Step 4.4：完成批次 4

范围：
- `Shared.Algorithm.HydraulicsTransientSimulation`
- `Rhapsody.Computation.HydraulicsTransient`

说明：
- 这是专项收尾批次
- 建议单独排期，不与其他仓库并行混提

建议 commit：
- Shared 相关改动单独若干 commit
- Actor 相关改动单独若干 commit
- 跟踪与基线更新单独 commit

## Phase 5：收尾

### Step 5.1：重新导出全量基线

操作：
- 运行 `scripts/export-repo-to-nuget-map.ps1`
- 运行 `scripts/export-package-versions.ps1`
- 运行 `scripts/find-package-version-conflicts.ps1`

验证：
- 结果能反映最终升级状态
- 非例外项的多版本冲突显著减少

建议 commit：
- `commit final-01`
  - 仅提交文档和报告刷新

### Step 5.2：更新最终状态

操作：
- 更新 [uni-pkg-version-target-baseline.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-target-baseline.md)
- 更新 [uni-pkg-version-upgrade-tracker.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-upgrade-tracker.md)
- 在 [uni-pkg-version-plan.md](D:\SLB\Prism\PA\tasks\uni-pkg-version-plan.md) 中补最终执行说明或经验总结

验证：
- 计划、基线、跟踪三份文档一致

建议 commit：
- `commit final-02`
  - 仅提交最终文档状态

## 最小执行单位

为了保证每一步都可 commit，执行时默认遵守下面的最小单位。

- 一个脚本 + 对应 README/doc 说明 = 一个 commit
- 一个基线文档 = 一个 commit
- 一个跟踪文档更新 = 一个 commit
- 一个 Shared 仓库的版本升级 = 一个 commit
- 一个 Shared 仓库的兼容修复 = 一个 commit
- 一个 Actor 仓库的内部包回灌 = 一个 commit
- 一个 Actor 仓库的 `.nuspec`/IntegrationTests/配置同步 = 一个 commit
- 一个 Actor 仓库的兼容修复 = 一个 commit

## Stop Rules

遇到以下情况时，不继续推进到下一步，而是在当前步骤内先处理完：

- 目标版本规则不明确
- Shared Pipeline 未产出可用真实版本
- Actor 仍引用旧内部包版本
- `.nuspec` 与工程版本不一致
- `restore/build/test` 失败且原因未定位
- README 或脚本文档未同步更新
