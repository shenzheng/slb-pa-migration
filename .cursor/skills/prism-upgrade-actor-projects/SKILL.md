---
name: prism-upgrade-actor-projects
description: >-
  Lists Prism Dapr 升级范围内、说明为「本次升级」的 Actor 工程目录名与仓库根下路径。
  Use when the user asks for 本次升级的 actor、升级涉及的 Actor 列表、Actors 升级范围，
  or which projects under Actors/ are in scope for the upgrade (excluding 参考工程 and 本次跳过).
---

# Prism 本次升级的 Actor 工程列表

## 何时使用

- 用户询问 **本次升级包含哪些 Actor**、**升级范围内的工程**、或需要 **与 ADO Repository 同名的目录列表**。
- 需要与 **文档一致** 的答案：以仓库内 `AGENTS.md` 为准，避免凭记忆列举。

## 权威来源（必须优先）

1. 打开仓库根目录 **`AGENTS.md`**，定位 **`### Actors`** 表格。
2. **只保留**「说明」列为 **`本次升级`** 的行。
3. **排除**：
   - `本次跳过`（当前为 `Rhapsody.Computation.CementingHydraulics`）
   - `参考工程`（`Rhapsody.Computation.DataGenerator`、`Rhapsody.Service.ActorDirector`、`Rhapsody.Service.StreamSampling`）

若 `.cursor/rules/prism-project-agents.mdc` 与 `AGENTS.md` 并存，二者应同步；**冲突时以 `AGENTS.md` 为准**。

## 回答时建议输出的内容

- **目录名**（与 Azure DevOps Repository / Pipeline 名称一致）。
- **本地路径**：`Actors/<目录名>/`（仓库根相对路径；Windows 下磁盘路径为 `<repo>\Actors\<目录名>\`）。
- **数量**：升级范围内 Actor **工程个数**（当前文档中为 **15**，以表格实际行为准）。

## 快照列表（便于快速作答；与 AGENTS 冲突时以 AGENTS 为准）

以下对应「说明 = 本次升级」的目录名（一行一个，便于复制）：

```text
Rhapsody.Computation.ChannelProjection
Rhapsody.Computation.DepthJumpCorrection
Rhapsody.Computation.Flowback
Rhapsody.Computation.HydraulicsTransient
rhapsody.computation.killsheet
Rhapsody.Computation.OperationKpi
Rhapsody.Computation.PackOff
Rhapsody.Computation.ProceduralAdherence
Rhapsody.Computation.Risk
Rhapsody.Computation.RtRheology
Rhapsody.Computation.TndBroomstick
Rhapsody.Computation.Udf
Rhapsody.Computation.WellBalanceRisks
Rhapsody.Service.DrillingKpi
Rhapsody.Service.PressureMonitoring
```

## 与「Actors 文件夹下全部子目录」的区别

`Actors/` 下可能存在 **未写入**上述表格的目录（例如其它实验或子模块）。回答 **「本次升级」** 时 **不要** 仅用文件系统枚举代替文档；若用户明确要求「磁盘上存在哪些 Actor 目录」，再单独说明并区分于升级范围。

## 相关文档

- Pipeline 与定义 ID：`doc/rhapsody-service-to-ado-pipeline-mapping.md`
- 升级 Pipeline 状态：`.cursor/skills/prism-ado-pipeline-status/SKILL.md`
