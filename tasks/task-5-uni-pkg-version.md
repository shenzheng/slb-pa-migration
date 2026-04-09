# 任务描述

这是为了制定一个尽可能将引用的包统一的升级计划。

参考文档：./doc/package-versions.md所有的package，我们希望尽可能将package统一为统一的版本。

这各任务是制定一个计划，制定下一步的改造计划。

这个计划需要满足以下要求：

- 每一个package尽可能采用最后一个版本（不是网上的最新版本，而是这些包的最新版本），并且在计划中说明
- 需要规划好先后顺序，如最底层的包先统一，然后Shared库再修改，最后才是Actor
- Shared Computation运行Pipeline后，会升级自身的版本号。例如“#1.0.0.15601898 • Merged PR 754424: [bjing] upgrade common layer”，需要提取出#1.0.0.15601898，供Actor的package引用时使用
- 整个升级过程需要是端到端的，包含Pipeline执行
- 规划后，需要制定出改造升级批次
- 需要有验证机制
- 如果某些可重用的步骤是可编程的，则可以规划出哪些脚本需要编写
- 该计划未来可复用，因为未来底层包还是可能升级的
- 信息收集和升级，都是在当前分支下的最新代码执行
- 有些工程不在本次升级范围内，请参考[不进行改造的工程](#不进行改造的工程)

## 不进行改造的工程

- Rhapsody.Computation.CementingHydraulics
- Rhapsody.Library.ComputationDaprAdapter
- Shared.Library.Computation.Common
- Rhapsody.Algorithm.DataGenerator
- Shared.Algorithm.CoreComputation
- Rhapsody.Computation.CoreComputation
- Rhapsody.Computation.DataGenerator
- Rhapsody.Service.ActorDirector
- Rhapsody.Service.StreamSampling

