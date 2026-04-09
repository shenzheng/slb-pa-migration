# 从 Actor Director 到算法 Actor 调用链文档编写计划

## Summary

编写一份面向 C# 开发者的 Markdown 文档，主题是“从 `Actor Director` 到算法 Actor 的调用链”。文档以 `Rhapsody.Service.ActorDirector` 和 `Rhapsody.Computation.HydraulicsTransient` 为主样例，结合 `Rhapsody.Library.ComputationDaprAdapter` 解释新架构中的注册、激活、启动、计算、日志与定制点，并用少量对比说明它相对旧 Service Fabric 模式的变化。  
输出目标是让读者能顺着一条真实链路回答这 5 个问题：入口在哪里、Actor 如何被发现并启动、算法如何接入、日志怎么看、问题怎么排查。

## Key Changes

### 文档范围与主线
- 以 1 条主线讲解调用链：`ActorDirector API/内部调度 -> ActorManager -> ComputationActorHelper/IActorHelper -> Dapr Actor Proxy -> HydraulicsTransient Actor Program -> BuildApplication<ComputationActor>() -> ComputationActorBase -> HydraulicsTransientSimulation`。
- 明确区分 3 条相关链路：
  1. 注册链路：算法 Actor 启动后如何向 Actor Director 注册自己。
  2. 激活链路：Actor Director 如何按配置和容器类型激活算法 Actor。
  3. 运行链路：Actor 被激活后如何加载配置、构建 pipeline、实例化算法类并开始处理数据。
- 把 `StreamSampling` 放在“关联链路”章节说明，只解释它和算法 Actor 的关系，不展开成另一份文档。

### 文档结构
- `1. 背景与阅读指南`
  说明旧架构与新架构名词对应关系，给出建议阅读顺序。
- `2. 总体架构图`
  放 1 张总览图，覆盖 Actor Director、配置来源、Dapr Actor、ComputationDaprAdapter、算法实现、日志。
- `3. 主调用链分步说明`
  按“谁调用谁、传什么、在哪个文件、产出什么状态/日志”的格式写。
- `4. 关键定制点`
  说明新增一个算法 Actor 时最关键的扩展点：
  `Program.cs`、`ComputationActor`、`GetComputationInstance`/算法入口、`OnPipelineCreated`、`appsettings.json` 的 `ProviderName`、容器类型与注册信息。
- `5. 配置与注册机制`
  说明 `AlgorithmConfigurationProvider`、Actor 注册信息、`ActorUri = Name-MajorVersion`、`Container`/`StartFrom`/黑白名单/Feature Setting` 对激活的影响。
- `6. 日志与排障`
  用“入口日志 -> 激活日志 -> Actor 激活日志 -> pipeline 配置日志 -> 常见失败点”的顺序给出定位方法。
- `7. 附录`
  放术语表、关键类索引、建议阅读代码路径。

### 图和图例
- 至少提供 3 个 Mermaid 图：
  1. 总体组件图。
  2. 激活时序图。
  3. Actor 内部启动/配置 pipeline 流程图。
- 图中节点名使用仓库内真实名称，不做泛化重命名。
- 图例需标注 3 类对象：
  控制面组件、运行时组件、算法实现组件。

### 编写方法
- 以源码为准，优先引用以下位置：
  `Actors/Rhapsody.Service.ActorDirector/...`
  `Actors/Rhapsody.Computation.HydraulicsTransient/...`
  `Shared/Rhapsody.Library.ComputationDaprAdapter/...`
- 每一节都要落到具体类或方法，不写空泛架构描述。
- 关键代码引用只做短摘录或摘要，避免大段贴代码。
- 文档默认写入 `doc/actor-director-call-chain.md`。
- 文档需满足 `markdownlint`，并保持 Windows CRLF。

## Test Plan

- 内容验收
  - 能从文档中明确找到主入口、注册入口、激活入口、算法入口、日志入口。
  - 能说清 `ActorDirector` 和算法 Actor 之间不是直接 new，而是通过 `IActorProxyFactory/CreateActorProxy` 调用。
  - 能说清算法 Actor 启动后会反向向 Actor Director 注册自身。
  - 能说清 `ComputationActorBase` 在运行链路中的职责，而不是只停留在 `ComputationActor` 表面。
- 定制验收
  - 读者能根据“关键定制点”章节列出新增算法 Actor 至少需要改哪些位置。
  - 读者能根据文档解释 `ProviderName`、`ActorUri`、`Container`、`StartFrom` 的作用。
- 排障验收
  - 文档至少覆盖 5 类常见问题：未注册、无法激活、拿不到 `ActorInfor`、租户解析失败、算法 DLL/类型找不到。
  - 每类问题都要给出推荐查看的日志关键词或对应类。
- 形式验收
  - Markdown lint 通过。
  - Mermaid 图能渲染。
  - 全文使用仓库内真实命名，文件路径和类名可在当前仓库中定位。
  - 文本文件换行为 CRLF。

## Assumptions

- 本任务产出的是“文档编写计划”，不是直接编写最终文档。
- 最终文档采用单文档形式，不拆成多篇。
- 主样例固定使用 `HydraulicsTransient`，参考补充可提及 `DataGenerator` 或 `DrillingKpi`，但不要求展开逐个 Actor。
- 文档读者是熟悉 C#、但不一定熟悉 Dapr Actor 和 Prism 改造背景的工程师。
- 不额外要求加入运行截图；图示以 Mermaid 为默认方案。
