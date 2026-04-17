# 任务描述

Rhapsody.Computation.DepthJumpCorrection在运行的日志中，其Actor没有执行到OnActivate的日志，需要分析可能原因以及如何进一步分析。

## 文档

- ./actor-director-call-chain.md，从actor director到actor的调用链，需要先学习

## 代码和目录

- ./Actors/Rhapsody.Computation.DepthJumpCorrection，Actor所在的工程
- ./Shared/Rhapsody.Library.ComputationDaprAdapter。DepthJumpCorrection，Actor所在的工程所属的基类
- ./Actors/Rhapsody.Service.ActorDirector，调用和激活计算Actor的根
- ./Tools/Prism-KibanaLog/samples/20260414-095547，相关日志。重点关注Slb.Prism.Rhapsody.Service.ActorDirector-3-20260414-095547-int.csv和Slb.Prism.Rhapsody.Service.DepthJumpCorrection-1-20260414-095547-int.csv

## 分析结论（执行记录）

说明：`actor-director-call-chain.md` 在仓库中的路径为 `./doc/actor-director-call-chain.md`。

### 1. 「OnActivate 日志」在代码里指什么

- Dapr Actor 的 `OnActivateAsync` 在 `ComputationActorBase` 中实现；**第一条成功路径日志**为 `{LogPrefix} {AlgorithmName} begin activate actor...`（见 `ComputationActorBase.OnActivateAsync`）。
- 若构造函数里 `LoadActorInfor()` 未拿到 `ActorInfor`，则 `OnActivateAsync` 在开头直接 `return`，**不会打「begin activate actor」**，也**不会**打文档表 8.1 中的 `activate actor succeed`（见下方代码引用）。

### 2. 样本日志中的直接证据

- **ActorDirector**（同一样本时间段）：`ActivateAllComputations` 汇总里列出的算法包含 `corecomputation,flowback,...,channelprojection,datagenerator` 等，**未出现 depthjumpcorrection**；且在该 CSV 中 **grep 不到 DepthJump 相关关键字**。
- **DepthJumpCorrection**：整份样本中 **没有** `begin activate` / `start invoked`；存在多条 `No actorinfor found for {guid}`（Warning）、对 `ActorDirector` 的 `actor/recompute/get?id=...` **HTTP 404**，以及 `deactivate actor succeed. By GC` / `By pause invoked`。

结论与调用链一致：**控制面未把该算法纳入「应激活列表」或实例侧拿不到 ActorInfor 时，不会出现预期的 OnActivate 成功日志。**

### 3. 可能原因（按优先级）

1. **算法未进入 ActorDirector 的激活集合**  
   `ActorManager.ActivateAllComputations` 只遍历 `AlgorithmConfigurationProvider.Actors`（来自 Mongo `ActorTypes_V3`）。若 DepthJumpCorrection 服务未成功注册、或缓存中无该条目，则不会出现 `Begin start actor: ... DepthJumpCorrection...`，也不会调用 `StartAsync()`。
2. **Container 与激活范围不一致**  
   `ActivateAllComputations(wellId, activeContainerId)` 内对 `container == "well"` 过滤（见 `ActorManager`）。若注册信息里 **Container 为 wellbore**，则不会在「当前 active well 容器」这一轮被激活（需对照注册表字段）。
3. **ShouldActivate 过滤**  
   黑名单 / `StartFrom` 与井创建时间 / Feature `ComputationNotRun` 会导致跳过（样本中可见 `Skip activate actor by blacklist` 其它算法，可对照 DepthJump 是否被同样跳过）。
4. **`ActorInfor` 为空导致 OnActivate 静默退出**  
   基类构造函数即调用 `GetActorInfor`；失败时仅有 Warning `No actorinfor found`，随后 `OnActivateAsync` 因 `ActorInfor == null` 直接返回，**无 Information 级「begin activate」**。这与样本中大量 Warning + 无 begin activate 一致。
5. **`StartAsync` 同样依赖 ActorInfor**  
   `StartAsync()` 在 `ActorInfor == null` 时直接返回，故也不会有 `Actor ... start invoked` 日志（样本中亦未出现）。

### 4. 建议的进一步排查步骤

1. **Kibana / 日志**：对同一 `wellId`、时间窗搜索 ActorDirector：`Activated all computations` 行是否包含 depthjumpcorrection；搜索 `Begin start actor` / `Start actor succeed` 是否含 DepthJumpCorrection 的 `ActorUri`（通常为 `DepthJumpCorrectionActor-{主版本}`，以注册为准）。
2. **Mongo `ActorTypes_V3`**：是否存在 DepthJumpCorrection（或 manifest 中的 `Name`）对应记录；**Container**、**StartFrom**、**ActorUri** 是否与环境与 ActorDirector 侧一致。
3. **DepthJumpCorrection 服务启动日志**：是否有 `Succeed to register actor` / ActorDirector 侧 `Registered actor configuration for`（见 `doc/actor-director-call-chain.md` 8.1）。
4. **ActorInfor**：对日志中 `No actorinfor found` 的 **ActorId**（即 Dapr `ActorId`）核对是否应为 **wellId** 或 **active wellboreId**；与 `GetActiveContainerId` 逻辑是否一致。
5. **recompute/get 404**：与「无 ActorInfor」同源排查——控制面是否从未为该 container 创建/保存 ActorInfor。

### 5. 可选改进（如需便于后续排障）

在 `ComputationActorBase.OnActivateAsync` 中，当 `ActorInfor == null` 时增加一条 **Information 或 Warning**（例如明确写出「跳过 OnActivate：ActorInfor 为空」），可避免与「从未调用 OnActivate」混淆。属产品/可观测性改动，需单独评审。

### 6. 代码引用

```112:116:d:\SLB\Prism\PA\Shared\Rhapsody.Library.ComputationDaprAdapter\ComputationDaprAdapter\ComputationActorBase.cs
        protected override async Task OnActivateAsync()
        {
            if (ActorInfor == null)
                return;
            stopped = false;
```

```331:340:d:\SLB\Prism\PA\Shared\Rhapsody.Library.ComputationDaprAdapter\ComputationDaprAdapter\ComputationActorBase.cs
        public async Task StartAsync()
        {
            if (ActorInfor == null)
                return;
            Logger?.Information($"{LogPrefix} Actor ({_AlgorithmName}): {StringId} start invoked.");
            if (stopped)
            {
                await OnActivateAsync();
            }
```

```103:118:d:\SLB\Prism\PA\Actors\Rhapsody.Service.ActorDirector\Slb.Prism.Rhapsody.Service.ActorDirector\ActorManager.cs
            var actorsForContainer = AlgorithmConfigurationProvider.Actors.Values.Where(a => a.Container == container);
            actorsForContainer = actorsForContainer.Where(a => !featureSettingBlackList.Contains($"{a.Name}-{a.Version}")).ToList();

            var activated = new ConcurrentBag<string>();            
            Parallel.ForEach(actorsForContainer, (actor) =>
            {
                var actorName = actor.Name.Replace(" ", "").ToLower();
                if (ShouldActivate(whitelist, blacklist, actorName, wellId, actor))
                {
                    computationActorHelper.ActivateContainerAsync(containerId, actor.ActorUri)
                        .Wait(new TimeSpan(0, 1, 0));
                    activated.Add(actorName);
                }
            });
            ActorCache.Set(containerId, DateTimeOffset.Now, DateTimeOffset.Now.AddMinutes(5));
            logger?.Information($"Activated all computations for {container}: {containerId}. Computations: {string.Join(",", activated)}");
```
