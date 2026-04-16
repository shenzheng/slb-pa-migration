# 从 Actor Director 到算法 Actor 的调用链

## 1. 背景与阅读指南

本文面向熟悉 C#、但不一定熟悉 Prism 新架构的开发者，目标是帮助读者从一条真实链路理解下面 5 个问题：

- 入口在哪里
- Actor 如何被发现并启动
- 算法如何接入
- 日志怎么看
- 问题怎么排查

本文以以下三个仓库内实现为主样例：

- `Actors/Rhapsody.Service.ActorDirector`
- `Actors/Rhapsody.Computation.HydraulicsTransient`
- `Shared/Rhapsody.Library.ComputationDaprAdapter`

建议按下面顺序阅读源码：

1. `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Controllers/ActorController.cs`
2. `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/ActorManager.cs`
3. `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Helper/ComputationActorHelper.cs`
4. `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Helper/ActorHelper.cs`
5. `Actors/Rhapsody.Computation.HydraulicsTransient/Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor/Program.cs`
6. `Actors/Rhapsody.Computation.HydraulicsTransient/Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor/ComputationActor.cs`
7. `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/Extensions/WebApplicationBuilderExtensions.cs`
8. `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/ComputationActorBase.cs`

在旧架构里，算法 Actor 运行在 Service Fabric Actor/Worker 模式上；在新架构里，Actor 模式保留，但运行时切换为 Dapr Actor，后台宿主切换为 ASP.NET Core。对调用链来说，最重要的变化是：

- `ActorDirector` 不再直接依赖 Service Fabric Actor Runtime，而是通过 `IActorProxyFactory.CreateActorProxy` 调用算法 Actor。
- 算法 Actor 不再靠 Service Fabric 启动入口注册自己，而是在 `BuildApplication<TActor>()` 阶段通过 `IActorDirectorService.Register(...)` 反向注册到 `ActorDirector`。
- 计算运行时被抽到 `ComputationActorBase` 和 `Rhapsody.Library.ComputationDaprAdapter` 中，具体算法 Actor 只保留少量定制点。

## 2. 总体架构图

```mermaid
flowchart LR
    subgraph Control["控制面组件"]
        AD["Rhapsody.Service.ActorDirector"]
        DB["ActorTypes_V3 / ActorInfor / Feature Setting"]
    end

    subgraph Runtime["运行时组件"]
        Proxy["IActorProxyFactory / Dapr Actor Proxy"]
        Adapter["Rhapsody.Library.ComputationDaprAdapter"]
        Dapr["Dapr Actor Runtime"]
    end

    subgraph Algo["算法实现组件"]
        HTActor["Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor"]
        Base["ComputationActorBase"]
        Sim["HydraulicsTransientSimulation"]
    end

    AD --> DB
    AD --> Proxy
    Proxy --> Dapr
    Dapr --> HTActor
    HTActor --> Adapter
    Adapter --> Base
    Base --> Sim
    HTActor -.启动注册.-> AD
    Base -.运行日志.-> AD
```

图例：

- 控制面组件：负责注册信息、激活决策、对外 API、上下文与配置查询
- 运行时组件：负责 Actor 宿主、代理调用、通用计算运行时
- 算法实现组件：负责算法 Actor 包装、算法实例、输出阶段

## 3. 三条关键链路

### 3.1 注册链路

注册链路发生在算法 Actor 服务启动时，而不是第一次业务调用时。

1. `HydraulicsTransient` 服务从 `Program.cs` 进入，执行 `builder.BuildApplication<ComputationActor>()`。
2. `Rhapsody.Library.ComputationDaprAdapter.Extensions.WebApplicationBuilderExtensions.BuildApplication<TActor>()` 完成 Dapr Actor 宿主、配置、外部服务、日志等初始化。
3. 该方法内部调用 `InitializeRegistration(containerType)`。
4. `InitializeRegistration(...)` 读取 `ComputationManifestProvider.AlgorithmConfiguration` 和程序集版本，生成注册信息：
   - `Name`
   - `Version`
   - `ActorUri = $"{config.Name}-{version.Major}"`
   - `Container`
   - `StartFrom`
   - 输入 Channels / TimeSeries / CriticalChannels
5. `RegisterActor(...)` 通过 `IActorDirectorService.Register(actor)` 把算法注册到 `ActorDirector`。
6. `ActorDirectorService.Register(...)` 最终调用 `ActorDirector` 的 `actortype` 接口。
7. `ActorDirector` 侧由 `ActorTypeController.Register(...)` 接收该请求，再调用 `IActorTypeAccessor.Upsert(model)`。
8. `ActorTypeAccessor` 最终把注册信息写入 Mongo 集合 `ActorTypes_V3`；如果当前环境带有 `Debugger` 后缀，则实际集合名会变成 `ActorTypes_V3_<Debugger>`。

这条链路的关键点是：算法 Actor 启动后会反向注册自己，所以 `ActorDirector` 激活算法 Actor 之前，必须先有可用的注册信息。

注册成功后，存下去的核心字段包括：

- `Name`
- `Version`
- `ActorUri`
- `Container`
- `StartFrom`
- `Channels`
- `TimeSeries`
- `CriticalChannels`

后续 `AlgorithmConfigurationProvider` 周期性从这个集合重新同步，因此这里是算法“是否存在、如何被激活、应该订阅什么输入”的控制面事实源。

#### 3.1.1 ActorInfor：与 ActorTypes 的区别、何时写入、写什么、何处读取

本节与上一节 **3.1 注册链路（ActorTypes_V3）** 并列，但描述的是 **另一张控制面数据**：**按容器（井 / 活跃井筒）存放的运行时上下文**，不是“算法类型定义”。

| 对比项 | `ActorTypes_V3`（算法注册） | `ActorInfo_Dapr` 集合中的 `ActorInfor`（实例上下文） |
| --- | --- | --- |
| 含义 | 某算法是否已向 ActorDirector 注册、`ActorUri`、输入通道、`StartFrom` 等 | 某个 **容器 Id**（Dapr `ActorId`）下，井与容器关系、实时/重算类型等 |
| 典型写入 | 各算法服务启动时 `PUT actortype` | 井/井筒生命周期与事件处理中 **Upsert** |
| 典型读取 | `AlgorithmConfigurationProvider`、激活前选算法 | 算法 Actor 构造时、`GET actor/recompute/get` / `GET actor/infor` |

Mongo 集合名在 `ActorInforAccessor` 中默认为 `ActorInfo_Dapr`（若配置 `Debugger` 后缀则集合名带后缀）。

##### 何时触发写入（Upsert）

以下路径均调用 `IActorInforAccessor.Upsert`，成功落库前由 `ActorInforAccessor` 打 **Information** 日志（见下文「关键日志」）：

1. **井创建（单井筒场景）**  
   `MessageHandlers/WellOrWellboreCreateMessageHandler.cs` 中 `ProcessWellCreateEventMessage`：在 **`!IsMultiWellbore(wellId)`** 时，先 Upsert 一条 **`Id = WellId = ContainerId`** 的实时 ActorInfor，再 **`ActivateAllComputations(wellId, true)`**。
2. **多井筒：活跃井筒确定**  
   `WellboreActivator.cs`：当前井筒被判定为 active 等逻辑后，Upsert **`Id = wellboreId`，`WellId = wellId`，`ContainerId = wellboreId`**，再 **`ActivateAllComputations`**。
3. **井状态类事件**  
   `MessageHandlers/EventMessageHandler.cs` 中 `ManageActors`：根据 **`actorManager.GetActiveContainerId(wellId)`** 得到 `activeContainerId`，先 Upsert **`Id = ContainerId = activeContainerId`**，再按活跃/暂停等分支调用 **`StartStreamingAsync`** 或 **`StopStreamingAsync`** 等（与暂停逻辑配合）。
4. **对外 API**  
   `Controllers/ActorController.cs` 的 **`POST actor/infor`**（`UpsertActorInfor`）：运维或调用方显式写入/更新。

##### 写入内容（核心字段）

文档以代码中常见 Upsert 为准：`Id`（与 Dapr **`ActorId`**、后续查询键一致）、`WellId`、`ContainerId`、`Type`（如 `ActorType.RealTime`）等；完整结构见 Contract 中 `ActorInfor` / `ActorInforDocument`。  
**要点**：算法激活时使用的 **`containerId`**（见 `ComputationActorHelper.ActivateContainerAsync(containerId, actorUri)`）必须与 **`ActorInfor.Id`** 所代表的容器一致，否则算法侧按 `ActorId` 拉取 ActorInfor 会得到空。

##### 何处读取

1. **算法 Actor 侧（运行时）**  
   `ComputationActorBase` 构造函数中 `LoadActorInfor()`：`StringId` 为当前 Actor 的 **`Id` 字符串**，调用 `IActorDirectorService.GetActorInfor(StringId)`，对应 HTTP **`GET actor/recompute/get?id={actorId}`**（实现见 `ComputationDaprAdapter/RemoteServices/ActorDirectorService.cs`）。成功后才进入 `OnActivateAsync` 中 `ConfigPipeline()` 等；若始终为 null，则 `OnActivateAsync` 开头即返回（无「begin activate actor」日志）。
2. **ActorDirector 侧（API）**  
   `ActorController` 的 **`GET actor/recompute/get`**（Obsolete 标注）与 **`GET actor/infor`**：均通过 `_actorInforAccessor.Get(id)` 按 **主键 `id`** 读 Mongo。

##### 关键日志（检索关键词）

| 位置 | 关键词 / 含义 |
| --- | --- |
| ActorDirector，写入 Mongo | **`Upsert ActorInfor`** + 序列化后的文档 JSON（`ActorInforAccessor.Upsert`） |
| ActorDirector，`appsettings` 中 `ProviderName` | 一般为 **`Slb.Prism.Rhapsody.Service.ActorDirector-{实例号}`**（与部署一致） |
| ActorDirector，激活算法 | **`Begin start actor:`**、`**Start actor succeed:**`（与 ActorInfor 是否已存在无直接日志绑定，但常与同一口井时间线相邻） |
| 算法服务，拉取成功 | **`Succeed to get actorinfor`**（`LoadActorInfor` 成功） |
| 算法服务，拉取失败 | **Warning `No actorinfor found for {id}`**；常伴随对 ActorDirector 的 HTTP **404**（无文档） |

**注意**：**`Succeed to register actor` / `Registered actor configuration for`** 属于 **3.1 算法类型注册**，与 **`Upsert ActorInfor`** 不是同一条链路；排查「有注册无 ActorInfor」时应分开看。

### 3.2 激活链路

激活链路是本文的主线，核心路径如下：

`ActorDirector API/内部调度 -> ActorManager -> ComputationActorHelper -> ActorHelper -> IActorProxyFactory.CreateActorProxy -> IAlgorithmActor.StartAsync`

```mermaid
sequenceDiagram
    participant API as "ActorController / 内部触发"
    participant Mgr as "ActorManager"
    participant Conf as "AlgorithmConfigurationProvider"
    participant CH as "ComputationActorHelper"
    participant AH as "ActorHelper"
    participant Dapr as "Dapr Actor Proxy"
    participant Algo as "HydraulicsTransient Actor"

    API->>Mgr: "ActivateAllComputations(...) / Create(...)"
    Mgr->>Conf: "读取已注册 Actor 配置"
    Mgr->>Mgr: "应用 Container / StartFrom / 白名单 / 黑名单 / Feature Setting"
    Mgr->>CH: "ActivateContainerAsync(containerId, actorUri)"
    CH->>AH: "GetActorAsync<IAlgorithmActor>(containerId, actorUri)"
    AH->>Dapr: "CreateActorProxy"
    Dapr->>Algo: "StartAsync()"
    Algo-->>Dapr: "Task"
    Dapr-->>CH: "返回"
    CH-->>Mgr: "记录成功/失败日志"
```

实际入口有两类：

- 对外 API 入口：`ActorController.Create(...)`、`ActorController.Reset(...)`、`ActorController.ResendContext(...)`
- 内部调度入口：`ActorManager.ActivateAllComputations(...)`

主流程中的关键职责如下：

- `ActorController`
  - 接收外部请求
  - 解析 `wellId`、`containerId`、算法名和版本
  - 在需要时触发 `StartStreamingAsync(...)`
- `ActorManager`
  - 读取已注册算法配置
  - 基于 `Container` 过滤 `well` / `wellbore`
  - 基于 `StartFrom`、白名单、黑名单、Feature Setting 决定某个算法是否应激活
  - 对每个目标算法调用 `ComputationActorHelper.ActivateContainerAsync(...)`
- `ComputationActorHelper`
  - 记录“开始启动 Actor”和“启动成功/失败”的日志
  - 通过 `IActorHelper` 获取 `IAlgorithmActor` 代理
  - 调用 `StartAsync()`
- `ActorHelper`
  - 不直接创建对象
  - 通过 `IActorProxyFactory.CreateActorProxy<T>(new ActorId(actorId), serviceUri)` 创建 Dapr Actor 代理

因此，`ActorDirector` 与算法 Actor 之间不是直接 `new` 出对象，而是通过 Dapr Actor Proxy 跨边界调用。

### 3.3 运行链路

运行链路需要区分两层触发：

- `StartAsync()` 触发的是“Actor 进入运行状态并开始监听输入”
- 真正触发算法执行的是“输入消息进入 pipeline”

也就是说，`ActorDirector` 负责把算法 Actor 拉起来，但算法真正开始计算，通常是由队列消息驱动的。

1. Dapr Actor Runtime 激活 `ComputationActor`。
2. `ComputationActor` 继承 `ComputationActorBase`，实际运行逻辑主要在基类。
3. `ComputationActorBase.OnActivateAsync()` 调用 `ConfigPipeline()`。
4. `ConfigPipeline()` 先通过 `_ServiceHub.ActorDirectorService.GetActorInfor(StringId)` 获取 `ActorInfor`。
5. 基类组装 `EngineContext`，包括：
   - `WellId`
   - `ContainerId`
   - `StateManager`
   - `Logger`
   - `AlgorithmConfiguration`
   - `OutputChannels`
   - `EngineConfiguration`
6. 基类通过 `ResourceDiscoveryService` 解析 tenant。
7. 基类调用 `SetInitialValues(...)` 设置部分初始输入。
8. 基类构造 `AzureComputationContext`。
9. `ComputationActor.GetComputationInstance(...)` 返回 `HydraulicsTransientSimulation` 实例。
10. 基类通过 `PipelineBuilder.BuildPipeline(...)` 创建 `ComputationPipeline`。
11. `ComputationActor.OnPipelineCreated(...)` 添加 `HydraulicStatePublishStage` 这一算法特有输出阶段。
12. `_PipelineEngine.Start()` 启动输入监听与 pipeline。
13. `ComputationPipeline.Start()` 调用 `InputStream.Start()`。
14. `InputStream` 在实时模式下通过 `MessageReceiver.CreateRmqReceiver(...)` 创建 RabbitMQ receiver。
15. RabbitMQ 收到消息后，`InputStream.InitializeStreamDataReceiver(...)` 中注册的 `OnMessageReceived` 回调开始执行：
    - 首次补查上下文
    - `ProcessMessages(...)`
    - `DoProcess(...)`
    - 各类 `IInputMessageHandler`
    - `ProcessNextStage(...)`
16. 对齐后的输入再进入计算阶段，最终调用具体算法实例，也就是 `HydraulicsTransientSimulation`。

```mermaid
flowchart TD
    A["IAlgorithmActor.StartAsync()"] --> B["ComputationActorBase.OnActivateAsync()"]
    B --> C["LoadActorInfor()"]
    C --> D["ConfigPipeline()"]
    D --> E["LoadAlgorithmConfiguration()"]
    D --> F["构造 EngineContext"]
    D --> G["解析 tenant / 初始值"]
    D --> H["构造 AzureComputationContext"]
    H --> I["ComputationActor.GetComputationInstance(...)"]
    I --> J["HydraulicsTransientSimulation"]
    J --> K["PipelineBuilder.BuildPipeline(...)"]
    K --> L["ComputationActor.OnPipelineCreated(...)"]
    L --> M["HydraulicStatePublishStage"]
    M --> N["_PipelineEngine.Start()"]
    N --> O["InputStream.Start()"]
    O --> P["RabbitMQ / Recomputer 输入"]
    P --> Q["InputMessageHandler"]
    Q --> R["HydraulicsTransientSimulation"]
```

这里最重要的判断是：`ComputationActor` 只是算法 Actor 的薄包装层，真正把“Actor 调用”转换成“计算引擎启动”的是 `ComputationActorBase`。

### 3.4 自检与旁路停机链路

除了主链路之外，算法 Actor 还有一条“自检自己是否已经不是当前活跃实例”的旁路。

`ComputationActorBase` 在激活时会启动 `pipelineMonitorTimer`，每 15 秒执行一次 `CheckActiveInstance(...)`：

1. 基类根据算法名和主版本重新拼出当前 `actorUri`
2. 通过 `ProxyFactory.CreateActorProxy<IAlgorithmActor>(this.Id, actorUri)` 调用同一个 Actor Id
3. 读取对端 `InstanceId()`
4. 如果返回的 `activeInstanceId` 与当前实例保存的 `instanceId` 不一致，说明自己已经不是活跃实例
5. 当前实例执行 `StopComputationPipeline(false, $"By active instance {activeInstanceId}")`

这条旁路的作用是：

- 避免同一个 `ActorId` 下出现两个实例同时跑 pipeline
- 在重平衡、重建或重复激活后，旧实例能够自停

所以，“Actor 是否已经被 deactivated”并不只靠外部 `PauseAsync()`，还会靠这条自检链路兜底。

## 4. 主调用链分步说明

下面按“谁调用谁、传什么、在哪个文件、产出什么状态/日志”的方式，把主链路拆开。

### Step 1: 入口进入 ActorDirector

常见入口：

- `ActorController.Create(ActorCreateModel createModel)`
- `ActorManager.ActivateAllComputations(string wellId, bool startStreaming = false)`
- `ActorController.ResendContext(...)`

传入的关键参数：

- `wellId`
- `containerId`
- `name`
- `version`
- `actorId`

产出：

- 选中的目标 `containerId`
- 待激活的算法清单
- 控制面日志，例如“谁触发了创建/重置/激活”

### Step 2: ActorDirector 读取可激活配置

关键类：

- `AlgorithmConfigurationProvider`
- `ActorTypeAccessor`

`AlgorithmConfigurationProvider` 会周期性从 `ActorTypeAccessor.Get()` 同步 Mongo 中的算法定义，并缓存到内存中。这里缓存的是“哪个算法可用、它的 `ActorUri` 是什么、属于哪种 `Container`、从什么时间开始支持”。

产出：

- `Actors`
- `StreamSamplingActor`
- `BatchSchedulerActor`

### Step 3: ActorManager 做激活决策

`ActorManager.ActivateAllComputations(...)` 会继续做几层过滤：

- `Container` 是否匹配 `well` 或 `wellbore`
- `StartFrom` 是否早于井创建时间
- 自定义数据里的 whitelist / blacklist
- Feature Setting 中 `ComputationNotRun` 的黑名单

产出：

- 真的需要激活的算法列表
- 跳过原因日志，例如：
  - 因黑名单跳过
  - 因井创建时间早于 `StartFrom` 跳过
  - 因缓存防抖跳过

### Step 4: ActorDirector 通过 Dapr Proxy 激活算法 Actor

`ComputationActorHelper.ActivateContainerAsync(containerId, actorUri)` 的关键动作是：

1. 记录开始日志
2. `actorHelper.GetActorAsync<IAlgorithmActor>(containerId, actorUri)`
3. `await actor.StartAsync()`
4. 记录成功或失败日志

`ActorHelper.GetActorAsync<T>(...)` 内部调用：

```csharp
proxyFactory.CreateActorProxy<T>(new ActorId(actorId), serviceUri)
```

这里的 `actorId` 通常就是 `containerId`，例如 `wellId` 或 `wellboreId`；`serviceUri` 则是注册时写入的 `ActorUri`，例如 `HydraulicsTransientActor-2` 这种“算法名 + 主版本号”的形式。

### Step 5: 算法 Actor 宿主启动

`HydraulicsTransient` 侧的入口非常薄：

- `Program.cs` 只做 `builder.BuildApplication<ComputationActor>()`

宿主初始化工作主要由 `BuildApplication<TActor>()` 完成：

- 配置日志
- 配置外部服务
- `BuildActorHost<TActor>()`
- `app.MapActorsHandlers()`
- 初始化配置代理
- 向 `ActorDirector` 注册当前算法

产出：

- 可被 Dapr 访问的 Actor 端点
- 已注册到 `ActorDirector` 的算法元数据

### Step 6: 基类启动计算引擎并接上消息入口

`ComputationActorBase` 做了绝大部分通用工作：

- 查询 `ActorInfor`
- 计算日志前缀
- 读取算法配置
- 构造 `EngineContext`
- 解析 tenant
- 绑定状态管理器
- 创建 `AzureComputationContext`
- 组装 pipeline
- 启动 `_PipelineEngine`
- 启动 `InputStream`
- 在实时模式下接入 RabbitMQ，在重算模式下接入 `Recomputer`

产出：

- 处于运行中的计算 pipeline
- 带 `well`、`container`、`instanceId` 的结构化日志
- 已经订阅并等待输入消息的算法 Actor

### Step 7: 具体算法接管

`HydraulicsTransient` 的定制逻辑主要集中在 `ComputationActor.cs`：

- `GetComputationInstance(...)`
  - 返回 `new HydraulicsTransientSimulation(...)`
- `OnPipelineCreated(...)`
  - 添加 `HydraulicStatePublishStage`
- `GetHydraulicState()`
  - 对外暴露一个算法专属的查询方法

这说明一个算法 Actor 的职责通常只有两类：

- 告诉基类“真正的算法实例是什么”
- 告诉基类“额外的输出阶段或专属接口是什么”

### Step 8: 实际消息如何触发算法执行

以实时模式为例，算法不是在 `StartAsync()` 里直接算一遍，而是按下面顺序被动触发：

1. `InputStream.Start()` 启动 RabbitMQ receiver
2. 消息到达后，`OnMessageReceived` 回调进入
3. `DefaultMessageHandlerFactory.GetHandlers(...)` 创建的一组消息处理器按对象类型解析消息
4. 这些 handler 把原始消息转成统一的输入字典，例如：
   - channel
   - wellbore
   - trajectory
   - fluid report
   - time series
5. 解析后的输入推进到下一 stage
6. pipeline 调用具体算法对象 `HydraulicsTransientSimulation`

所以“算法被触发”的本质是：

- 外部：`ActorDirector` 先把 Actor 激活起来
- 内部：RabbitMQ 或 Recompute 输入把数据送进 `InputStream`
- 算法：只有拿到输入后才真正执行

## 5. StreamSampling 与算法 Actor 的关系

`StreamSampling` 不是本文主线，但它和算法 Actor 的激活顺序相关。

在 `ActorManager.StartStreamingAsync(...)` 和 `ActorController.Create(...)` 中，通常会先确保 `StreamSamplingActor` 被启动，再启动算法 Actor。原因是算法 Actor 的实时输入依赖采样流或上下文重发。

相关类：

- `SamplingActorHelper`
- `IStreamSamplingActor`

可以把它理解为：

- `StreamSamplingActor` 负责“喂数据”
- 算法 Actor 负责“做计算”

本文不展开 `StreamSampling` 内部实现，只把它视为算法 Actor 的上游依赖。

## 6. 关键定制点

如果要新增一个算法 Actor，最关键的定制点如下。

### 6.1 `Program.cs`

保持入口极薄，通常只需要：

```csharp
var builder = WebApplication.CreateBuilder(args);
var app = builder.BuildApplication<ComputationActor>();
app.Run();
```

这里最重要的是让宿主通过 `BuildApplication<TActor>()` 接入统一运行时。

### 6.2 `ComputationActor`

这是每个算法最核心的包装类，通常需要做三件事：

- 继承 `ComputationActorBase`
- 实现自己的 Actor 接口，例如 `IHydraulicsTransientActor`
- 覆盖必要的定制点

最常见的覆盖点：

- `GetComputationInstance(...)`
- `OnPipelineCreated(...)`

### 6.3 算法入口

`GetComputationInstance(...)` 负责把 Actor 与真实算法类连接起来。以 `HydraulicsTransient` 为例，返回的是 `HydraulicsTransientSimulation`。

如果不想手写实例化逻辑，基类默认也支持按配置中的 `EntryPoint` 反射加载算法 DLL 和类型；但像 `HydraulicsTransient` 这样直接 new 出实例，通常更直观。

### 6.4 输出阶段

如果算法需要额外输出、发布状态、转换结果，就在 `OnPipelineCreated(...)` 里往 pipeline 增加 stage。

`HydraulicsTransient` 的样例是：

- `HydraulicStatePublishStage`

### 6.5 `appsettings.json`

文档重点关注日志配置，尤其是：

- `LoggerSetup.EnricherConfiguration.Properties.ProviderName`

它需要和服务名对应。例如 `HydraulicsTransient` 使用：

- `Slb.Prism.Rhapsody.Service.HydraulicsTransientActor-2`

这个值会直接影响日志平台中的来源识别与检索体验。

### 6.6 容器类型与注册信息

新增算法时还需要确认：

- `Container` 是 `well` 还是 `wellbore`
- `ActorUri` 是否符合 `Name-MajorVersion`
- `StartFrom` 是否正确
- 输入 Channels / TimeSeries / CriticalChannels 是否完整

这些信息最终决定：

- `ActorDirector` 能否找到它
- `ActorManager` 会不会激活它
- `StreamSampling` 会不会为它订阅正确的数据

## 7. 配置与注册机制

### 7.1 `ActorUri`

`ActorUri` 不是随便写的字符串，而是由算法名和程序集主版本拼出来：

- `ActorUri = $"{config.Name}-{version.Major}"`

这意味着：

- 同一算法的大版本升级会产生新的 Actor URI
- `ActorDirector` 激活时必须用注册时保存的 `ActorUri`

### 7.2 `Container`

`Container` 决定算法挂在哪一层数据容器上：

- `well`
- `wellbore`

如果 Mongo 里未配置，`ActorTypeAccessor` 和 `AlgorithmConfigurationProvider` 都会把默认值补成 `well`。

### 7.3 `StartFrom`

`ActorManager.ShouldActivate(...)` 会比较井创建时间与 `StartFrom`。如果井创建时间早于算法支持时间，Actor 会被跳过，并留下说明日志。

### 7.4 黑白名单与 Feature Setting

Actor 是否激活还会受到以下因素影响：

- `CustomData` 中的 `whitelist`
- `CustomData` 中的 `blacklist`
- Feature Setting 中的 `ComputationNotRun`

因此，当一个算法“已经注册但没有启动”时，不能只看注册表，还要看这些控制项。

## 8. 日志与排障

推荐按“注册日志 -> 入口日志 -> 激活日志 -> Actor 激活日志 -> 消息日志 -> 算法日志 -> 输出日志”的顺序排查。

## 8.1 关键路径点与日志对照

下面这张表可以把“看到哪些日志”直接对应到“代码大概已经执行到哪里”。

| 路径点 | 代表日志关键词 | 说明 |
| --- | --- | --- |
| 算法向 ActorDirector 注册 | `Succeed to register actor` | 算法服务启动，`BuildApplication<TActor>()` 已执行到注册环节 |
| ActorDirector 落库注册信息 | `Registered actor configuration for` | `ActorTypeController.Register(...)` 已接收并写入 `ActorTypes_V3` |
| ActorDirector 开始激活 | `Begin start actor:` | `ComputationActorHelper.ActivateContainerAsync(...)` 已开始 |
| ActorDirector 激活成功 | `Start actor succeed:` | Dapr Proxy 调用 `StartAsync()` 成功返回 |
| Actor 激活开始 | `begin activate actor` | `ComputationActorBase.OnActivateAsync()` 已进入 |
| ActorInfor 已拿到 | `Succeed to get actorinfor` | `LoadActorInfor()` 成功 |
| Pipeline 已构建 | `Build pipeline for algorithm` | `PipelineBuilder.InitializeVersion(...)` 已执行 |
| Pipeline 配置完成 | `Succeed to config computation pipeline` | `ConfigPipeline()` 已完成 |
| InputStream 已开始处理初始化上下文 | `Query initial inputs:` / `set initial inputs:` | Actor 已开始拉取初始上下文 |
| 实时消息已进来 | `Processed initial inputs` / `message ... cannot be handled` / `Save state when InputStream receives context data` | `InputStream.ProcessMessages(...)` 已执行 |
| 算法 stage 已开始执行 | `pressure profile computation stage start` | `HydraulicsProfileComputation.ProcessMandatory(...)` 已进入 |
| 算法实际产出成功 | `RT simulation output successfully` | 一次实时液压计算成功完成 |
| 输出阶段已发消息 | `HydraulicStatePublish Stage Enter` / `HydraulicStatePublish message` | `HydraulicStatePublishStage` 已把结果发出 |
| Actor 自检活跃实例 | `Succeed to check active instance` | `CheckActiveInstance()` 自检已执行 |
| 旧实例自停 | `deactivate actor succeed. By active instance` | 当前实例发现自己不是活跃实例并停止 pipeline |

## 8.2 注册日志

先看两边是否完成注册：

- 算法 Actor 服务：
  - `Succeed to register actor ...`
- `ActorDirector`：
  - `Registered actor configuration for ...`

如果前者有、后者没有，优先看 `ActorDirectorService.Register(...)` 到 `actortype` 的网络链路。

## 8.3 入口日志

再看 `ActorDirector`：

- `ActorController`
- `ActorManager`
- `ComputationActorHelper`

重点关键词：

- `creates actor`
- `Activated all computations`
- `Begin start actor`
- `Start actor succeed`
- `Start actor failed`

如果这里已经失败，问题一般在：

- 算法未注册
- `ActorUri` 不对
- `containerId` 不对
- 过滤条件导致未被选中

## 8.4 Actor 激活日志

再看算法 Actor 服务：

- `begin activate actor`
- `activate actor succeed`
- `activate actor failed`

这些日志主要来自 `ComputationActorBase.OnActivateAsync()`。

## 8.5 Pipeline 与消息日志

如果 Actor 已被调起，但计算没跑起来，继续看：

- `Succeed to get actorinfor`
- `Succeed to config computation pipeline`
- `Query initial inputs`
- `set initial inputs`
- `Processed initial inputs`
- `Messages handlers initialized`
- `Failed to get tenant`
- `Cannot find module`
- `Cannot find type`

这些日志分别对应：

- `ComputationActorBase.LoadActorInfor()`
- `ComputationActorBase.ConfigPipeline()`
- `InputStream.QueryInitialInputs()`
- `DefaultMessageHandlerFactory.GetHandlers(...)`
- `InputStream.ProcessMessages(...)`

如果激活日志成功、但没有消息相关日志，优先怀疑：

- 队列没有输入
- `StreamSampling` 没有把数据喂进来
- RabbitMQ receiver 没有真正收到消息

## 8.6 算法执行日志

对 `HydraulicsTransient`，最关键的算法日志来自 `HydraulicsProfileComputation`：

- `pressure profile computation stage start`
- `trying to create RT Simulator`
- `trying to simulate real time data`
- `RT simulation output successfully`
- `RT simulator is null`
- `RT input content is null`

这组日志能帮助判断：

- 引擎是否已创建
- 这次时间步是否真的进了计算
- 输出是否成功
- 是“没有输入”还是“引擎没建起来”

## 8.7 常见问题清单

### 问题 1：算法未注册

现象：

- `ActorDirector` 找不到算法配置
- `ActorTypeAccessor.Get(name, version)` 结果为空

优先检查：

- 算法服务是否成功启动
- `BuildApplication<TActor>()` 是否执行了注册
- `ActorDirectorService.Register(...)` 是否成功

### 问题 2：无法激活

现象：

- 有注册记录，但 `ActorManager` 没有真的调 `StartAsync()`

优先检查：

- `Container` 是否匹配
- `StartFrom` 是否导致被跳过
- whitelist / blacklist
- Feature Setting 黑名单

### 问题 3：拿不到 `ActorInfor`

现象：

- Actor 端日志出现 `No actorinfor found`

优先检查：

- `ActorDirectorService.GetActorInfor(...)` 是否可访问
- `actorId` 是否正确
- `ActorInfor` 是否已提前写入

### 问题 4：租户解析失败

现象：

- `Failed to get tenant for well ...`

优先检查：

- `ResourceDiscoveryService`
- `wellId` / `containerId` 是否传错

### 问题 5：算法 DLL 或类型找不到

现象：

- `Cannot find module ...`
- `Cannot find type ...`

优先检查：

- 算法 DLL 是否被正确打包到服务目录
- `EntryPoint` 是否与实际类型名一致
- 版本或包内容是否正确

### 问题 6：Actor 已启动，但没有真正执行算法

现象：

- 看得到 `Start actor succeed`
- 看得到 `activate actor succeed`
- 但看不到算法 stage 日志

优先检查：

- 是否有 `Query initial inputs`、`Processed initial inputs`
- 是否有 `Messages handlers initialized`
- RabbitMQ 是否真的有消息
- `StreamSampling` 是否已启动并订阅对应算法

### 问题 7：当前实例被旁路停掉

现象：

- 周期性看到 `Succeed to check active instance`
- 随后出现 `deactivate actor succeed. By active instance ...`

说明：

- 当前实例检测到另一个同 `ActorId` 的实例已经成为活跃实例
- 当前实例主动停止 pipeline，这是预期保护行为，不一定是故障

## 9. 算法实际执行示例

以 `HydraulicsTransientSimulation` 为例，实际执行的不是一个单函数，而是一组顺序 stage：

- `BhaRunHandler`
- `ContextInputHandler`
- `RealTimeInputOrganizer`
- `HydraulicsProfileComputation`
- `HCIAlarmNotification`
- `TransientTrippingStage`

其中最值得关注的是 `HydraulicsProfileComputation`。一次典型的实时计算大致会做下面这些事：

1. 检查上下文是否已经完整，例如 tubular、wellbore geometry、fluid、trajectory 等
2. 如果实时模拟器还没创建，或者上下文变化导致需要重建，就创建或重建 RT simulator
3. 如果轨迹、泥浆、摩阻系数、surface cooling 等配置变化，就更新引擎内部状态
4. 如果当前时间步有实时输入，则调用液压引擎执行瞬态模拟
5. 从引擎输出中提取关键结果，例如：
   - `ECDAtBit`
   - `ESDAtBit`
   - `StandPipePressure`
   - `HoleCleaningIndex`
   - 温度剖面
   - 压力剖面
6. 把结果写回 `Output`
7. `HydraulicStatePublishStage` 再把其中的液压状态消息发到路由：
   - `p3.{WellId}.HydraulicState.{ContainerId}`

换句话说，`HydraulicsTransient` 并不是“收到消息就直接吐一个值”，而是：

- 先做上下文和实时输入整理
- 再驱动液压瞬态模拟引擎
- 再整理成压力剖面、hole cleaning profile、状态消息等多种输出

## 10. 推荐阅读代码路径

- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Database/ActorInforAccessor.cs`（`Upsert ActorInfor` 日志）
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/MessageHandlers/WellOrWellboreCreateMessageHandler.cs`（井创建时 Upsert）
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/WellboreActivator.cs`（多井筒活跃井筒 Upsert）
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/MessageHandlers/EventMessageHandler.cs`（`ManageActors` 中 Upsert）
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Controllers/ActorController.cs`
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/ActorManager.cs`
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Helper/ComputationActorHelper.cs`
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Helper/ActorHelper.cs`
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Helper/AlgorithmConfigurationProvider.cs`
- `Actors/Rhapsody.Service.ActorDirector/Slb.Prism.Rhapsody.Service.ActorDirector/Database/ActorTypeAccessor.cs`
- `Actors/Rhapsody.Computation.HydraulicsTransient/Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor/Program.cs`
- `Actors/Rhapsody.Computation.HydraulicsTransient/Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor/ComputationActor.cs`
- `Actors/Rhapsody.Computation.HydraulicsTransient/Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor/appsettings.json`
- `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/Extensions/WebApplicationBuilderExtensions.cs`
- `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/ComputationActorBase.cs`
- `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/InputStream/InputStream.cs`
- `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/InputStream/DefaultMessageHandlerFactory.cs`
- `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/RemoteServices/ActorDirectorService.cs`
- `Shared/Rhapsody.Library.ComputationDaprAdapter/ComputationDaprAdapter/RemoteServices/ServiceHub.cs`
- `Shared/Shared.Algorithm.HydraulicsTransientSimulation/Slb.Prism.Shared.Algorithm.HydraulicsTransientSimulation/HydraulicsTransientSimulation.cs`
- `Shared/Shared.Algorithm.HydraulicsTransientSimulation/Slb.Prism.Shared.Algorithm.HydraulicsTransientSimulation/Framework/HydraulicsProfileComputation.cs`

## 11. 术语表

- `ActorDirector`
  - 控制面服务，负责注册、查询、激活辅助、上下文和状态相关 API
- `AlgorithmActor`
  - 运行具体算法的 Dapr Actor
- `ActorUri`
  - Actor 的逻辑服务名，通常是“算法名 + 主版本号”
- `ActorInfor`
  - Actor 实例运行所需的上下文信息，例如 `WellId`、`ContainerId`、运行模式等；写入时机与读取路径见 **§3.1.1**
- `Container`
  - 算法运行绑定的数据容器层级，常见为 `well` 或 `wellbore`
- `ComputationActorBase`
  - 统一封装 Actor 生命周期、配置、上下文、pipeline、状态与日志的通用基类
- `StreamSamplingActor`
  - 为算法提供实时输入流或订阅管理的上游 Actor
- `InputStream`
  - pipeline 的输入入口，负责从 RabbitMQ 或重算输入中取消息并推进到后续 stage

## 12. 小结

把整条链路压缩成一句话，就是：

`ActorDirector` 先根据注册信息和控制规则决定“该启动谁”，再通过 `IActorProxyFactory` 调用算法 Actor 的 `StartAsync()`；算法 Actor 宿主由 `BuildApplication<TActor>()` 建好，真正的计算启动由 `ComputationActorBase` 完成，具体算法只需要在 `ComputationActor` 中接上自己的计算实例和输出阶段。

理解这句话后，新增一个算法 Actor、定位一次启动失败、或者解释新架构相对旧 Service Fabric 方案的变化，都会容易很多。
