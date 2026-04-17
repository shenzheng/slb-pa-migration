# 任务描述

## 范围（重要）

分析对象应为 **本次升级涉及到的全部 Actor 工程**，**不是**单独一个仓库（例如仅 DepthJumpCorrection）。

- **权威列表**：仓库根目录 `AGENTS.md` → **`### Actors`** 表格中，「说明」为 **`本次升级`** 的每一行（与 Azure DevOps Repository 同名的目录名）。
- **快速清单**：`.cursor/skills/prism-upgrade-actor-projects/SKILL.md`（与 `AGENTS.md` 冲突时以 `AGENTS.md` 为准）。
- **不在范围内**：`本次跳过`、`参考工程`（见表格说明列）。

对 **每一个** 升级范围内的算法服务，在日志与调用链上应能回答：**是否被 ActorDirector 激活**、**激活时的 ActorUri（日志中的写法）**、**ActorInfor 是否可能被写入/为何拿不到**、**是否被黑名单 / StartFrom / Feature 等过滤**。

下文以 **DepthJumpCorrection** 作为 **具体日志样本与排查示例**（同一套方法可迁移到其他 Actor：替换 `ProviderName`、`Activated all computations` 中的算法名、`Begin start actor` 中的 `ActorUri`）。

---

## 现象（示例）

以 **Rhapsody.Computation.DepthJumpCorrection** 为例：运行日志中 **看不到** 基类预期的 **`begin activate actor`** / **`activate actor succeed`**（见 `doc/actor-director-call-chain.md` §8.1、`ComputationActorBase`）。

---

## 需要给出的分析（至少包含，且对每个相关 Actor 通用）

1. **是否被 ActorDirector 激活**：在 ActorDirector 日志中是否存在针对该算法的 **`Begin start actor:`** / **`Start actor succeed:`** / **`Start actor failed:`**；**`Activated all computations`** 汇总里是否出现该算法（名称多为小写、去空格后的形式）。**激活时的名称**：Mongo `ActorTypes_V3` 中的 **`ActorUri`**（一般为 `{AlgorithmConfiguration.Name}-{主版本}`），与日志中 **`Begin start actor: {ActorUri} - {containerId}`** 一致。
2. **ActorInfor**：是否有 **`Upsert ActorInfor`**（控制面）；算法侧 **`GetActorInfor`** / **`No actorinfor found`**；与 **`doc/actor-director-call-chain.md` §3.1.1** 一致。
3. **时间与井筒（若任务给出时间窗）**：例如北京时间 **2026-04-16 10:10:00** 起，从 ActorDirector / 各算法 **`providerName`** 日志中归纳 **Well / Wellbore（containerId）** 与 **correlationId**。
4. **过滤条件**：井 **`blacklist` / `whitelist`**、**`Should activate ... StartFrom`**、Feature **`ComputationNotRun`** 等是否导致 **未调用 `StartAsync`** 或 **ActorInfor 与 Dapr ActorId 不一致**。

---

## 文档

- `./doc/actor-director-call-chain.md`（含 ActorTypes 与 ActorInfor、§3.1.1）

## 代码与目录（共享）

- `./Shared/Rhapsody.Library.ComputationDaprAdapter`（`ComputationActorBase`、注册与 `GetActorInfor`）
- `./Actors/Rhapsody.Service.ActorDirector`（`ActorManager`、`ComputationActorHelper`、ActorInfor Upsert）

## 各 Actor 工程路径

- `./Actors/<AGENTS 表格「本次升级」目录名>/`（每个算法一个目录；**共 15 个**，以 `AGENTS.md` 为准）

## 日志样本（示例）

- `./Tools/Prism-KibanaLog/samples/20260416-102821`（若存在）：重点关注 **`Slb.Prism.Rhapsody.Service.ActorDirector-3-...-int.csv`** 与各算法服务 **`Slb.Prism.Rhapsody.Service.<算法>-...-int.csv`**；DepthJumpCorrection 对应 **`...DepthJumpCorrection-1-...`**。

分析其他升级内 Actor 时，将 **`ProviderName`**、**`Begin start actor` 中的 ActorUri`** 换成该工程的 **`appsettings.json` → LoggerSetup → ProviderName** 与注册名即可。
