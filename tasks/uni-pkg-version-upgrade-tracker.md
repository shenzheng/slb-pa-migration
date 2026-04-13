# 引用包统一升级跟踪表

## 使用说明

- 本表用于跟踪 `tasks/uni-pkg-version-plan.md` 中纳入范围的仓库升级进度。
- 建议按批次推进，先完成 `Package Update`，再记录 `Build`、`Test`、`Pipeline`、`Produced Version`，最后回填 `Actor Backfill`。
- 状态建议统一使用 `Pending`、`In Progress`、`Done`、`Blocked`、`N/A`。
- `Actor Backfill` 仅适用于 Actor 仓库，Shared 仓库可填 `N/A`。
- `Updated At` 建议写入 `YYYY-MM-DD HH:mm`，便于按时间排序和筛查。
- task-5 已明确排除的仓库不在本模板中预填，避免和本轮范围冲突。

## Batch 0 - 基线与工具准备

本批次主要用于脚本、基线和说明文档准备，不对应具体仓库行。

## Batch 1 - 已有完成样例邻近仓库

| Repository | Batch | Type | Package Update | Build | Test | Pipeline | Produced Version | Actor Backfill | Risk | Blocker | Owner | Updated At |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Rhapsody.Algorithm.ChannelProjection | 1 | Shared | In Progress | Done | Done | Pending | - | N/A | Low | 当前真实阻塞是外部依赖版本不一致：`.csproj` 中 `Newtonsoft.Json = 13.0.1`，`.nuspec dependencies` 中为 `12.0.3`；不修改 `nuspec <version>` 和程序集版本 | - | 2026-04-10 03:20 |
| Rhapsody.Computation.ChannelProjection | 1 | Actor | Pending | Done | Done | Pending | - | Waiting for shared produced version | Low | 当前无须处理包自身版本；等待 Shared pipeline 产出真实版本号后，仅回灌 `Slb.Prism.Rhapsody.Algorithm.ChannelProjection` 的 `PackageReference` | - | 2026-04-10 03:20 |
| Shared.Algorithm.PressureMonitoring | 1 | Shared | Pending | Pending | Pending | Pending | - | N/A | Low | - | - | - |
| Rhapsody.Service.PressureMonitoring | 1 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | Low | - | - | - |
| Shared.Library.DrillingKpi | 1 | Shared | Pending | Pending | Pending | Pending | - | N/A | Low | - | - | - |
| Rhapsody.Service.DrillingKpi | 1 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | Low | - | - | - |

## Batch 2 - 单算法 Actor 成对改造

| Repository | Batch | Type | Package Update | Build | Test | Pipeline | Produced Version | Actor Backfill | Risk | Blocker | Owner | Updated At |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Shared.Algorithm.CementingHydraulics | 2 | Shared | Pending | Pending | Pending | Pending | - | N/A | Medium | - | - | - |
| Shared.Algorithm.Flowback | 2 | Shared | Pending | Pending | Pending | Pending | - | N/A | Medium | - | - | - |
| Rhapsody.Computation.Flowback | 2 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | Medium | - | - | - |
| Shared.Algorithm.KillSheet | 2 | Shared | Pending | Pending | Pending | Pending | - | N/A | Medium | - | - | - |
| rhapsody.computation.killsheet | 2 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | Medium | - | - | - |
| Shared.Algorithm.OperationKpi | 2 | Shared | Pending | Pending | Pending | Pending | - | N/A | Medium | - | - | - |
| Rhapsody.Computation.OperationKpi | 2 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | Medium | - | - | - |
| Shared.Algorithm.PackOff | 2 | Shared | Pending | Pending | Pending | Pending | - | N/A | Medium | - | - | - |
| Rhapsody.Computation.PackOff | 2 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | Medium | - | - | - |
| Shared.Algorithm.ParameterAdherence | 2 | Shared | Pending | Pending | Pending | Pending | - | N/A | Medium | - | - | - |
| Rhapsody.Computation.ProceduralAdherence | 2 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | Medium | - | - | - |

## Batch 3 - 差异性较高仓库

| Repository | Batch | Type | Package Update | Build | Test | Pipeline | Produced Version | Actor Backfill | Risk | Blocker | Owner | Updated At |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Rhapsody.Algorithm.DepthJumpCorrection | 3 | Shared | Pending | Pending | Pending | Pending | - | N/A | High | - | - | - |
| Rhapsody.Computation.DepthJumpCorrection | 3 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | High | - | - | - |
| Rhapsody.Algorithm.Risk | 3 | Shared | Pending | Pending | Pending | Pending | - | N/A | High | - | - | - |
| Rhapsody.Computation.Risk | 3 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | High | - | - | - |
| Rhapsody.Algorithm.Udf | 3 | Shared | Pending | Pending | Pending | Pending | - | N/A | High | - | - | - |
| Rhapsody.Computation.Udf | 3 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | High | - | - | - |
| Shared.Algorithm.RtRheology | 3 | Shared | Pending | Pending | Pending | Pending | - | N/A | High | - | - | - |
| Rhapsody.Computation.RtRheology | 3 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | High | - | - | - |
| Shared.Algorithm.TnDBroomstick | 3 | Shared | Pending | Pending | Pending | Pending | - | N/A | High | - | - | - |
| Rhapsody.Computation.TndBroomstick | 3 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | High | - | - | - |
| Shared.Library.WellBalanceRisks | 3 | Shared | Pending | Pending | Pending | Pending | - | N/A | High | - | - | - |
| Rhapsody.Computation.WellBalanceRisks | 3 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | High | - | - | - |

## Batch 4 - 高风险链路专项

| Repository | Batch | Type | Package Update | Build | Test | Pipeline | Produced Version | Actor Backfill | Risk | Blocker | Owner | Updated At |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Shared.Algorithm.HydraulicsTransientSimulation | 4 | Shared | Pending | Pending | Pending | Pending | - | N/A | High | - | - | - |
| Rhapsody.Computation.HydraulicsTransient | 4 | Actor | Pending | Pending | Pending | Pending | - | Pending shared version | High | - | - | - |

## 记录建议

- 如果某仓库的 `Package Update` 已完成但验证未通过，请在 `Blocker` 中写明具体失败点。
- 如果 `Pipeline` 已完成，请把 `Produced Version` 更新为真实产物版本号，不要沿用旧占位值。
- 如果 Actor 已完成回灌，请在 `Actor Backfill` 中写明所引用的 Shared 产物版本来源。
- 建议每次更新后同步刷新 `Updated At`，保持本表可用于批次推进检查。

## ChannelProjection 试点回填模板

- Shared 完成 pipeline 后：
  - `Rhapsody.Algorithm.ChannelProjection`
  - `Pipeline = Done`
  - `Produced Version = <Shared 真实版本号>`
- Actor 完成回灌并发版后：
  - `Rhapsody.Computation.ChannelProjection`
  - `Pipeline = Done`
  - `Produced Version = <Actor 真实版本号>`
  - `Actor Backfill = Shared <Shared 真实版本号>`
