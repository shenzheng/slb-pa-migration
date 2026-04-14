---
description: Prism 算法平台改造项目 — 与仓库根目录 AGENTS.md 对齐的全局说明
alwaysApply: true
---

# Prism 算法平台改造项目

> 本规则与 `AGENTS.md` 等价；修改时请同步更新 `AGENTS.md`（或二选一作为唯一来源）。

## 项目概述

这是一个老项目的升级工作，技术栈是以下情况

- 所有的程序都是C#的
- 包管理使用Nuget
- CI/CD使用Azure DevOps

## 老项目概述

- 老项目主要使用.Net Framework
- 使用Windows Service Fabric
- 主要会使用Service Fabric的Actor或Worker模式，如Stateless Worker
- Actor是算法实现的入口。算法的代码在另外的Package当中
  - Actor通常会继承于ComputationActorBase，通过重载方法对外提供
- 底层消息通讯使用RabbitMQ
- 目标部署环境是Virtual Machine Scale Set（Windows Server）

## 新项目概述

- 新项目使用.Net 10
- PlatformTarget为x64
- Actor模式不变，使用Dapr的Actor
- 如果是后台服务，则使用asp.net的服务
- 服务名称需要更换，如原来是Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor，则需要改为Slb.Prism.Rhapsody.Service.HydraulicsTransientActor
- 部署时需要nuspec打包，因为有集成测试等要求
- 部署方式使用Docker方式，最终会部署在AKS上
- 部署需要Helm Chart

## 目录结构

```pre
├─ Actors
|  ├─ Rhapsody.Computation.ChannelProjection
|  ├─ Rhapsody.Computation.DepthJumpCorrection
|  └─ ...
|
├─ Pipeline
|  ├─ CD
|  ├─ DevOps.Service.SSS
|  └─ rcis-devops-template
|
├─ scripts
|  ├─ normalize-crlf.ps1
|  └─ ...
|
└─ Shared
   ├─ Rhapsody.Library.ComputationDaprAdapter
   ├─ Shared.Library.Computation.Common
   └─ ...
```

### Actors

本次改造涉及到的所有Actors，下面的目录名和对应的Repository以及Pipeline是一样的。

| 目录                                     | Repository | 说明     |
| ---------------------------------------- | ---------- | -------- |
| Rhapsody.Computation.CementingHydraulics | 与目录同名 | 本次跳过 |
| Rhapsody.Computation.ChannelProjection   | 与目录同名 | 本次升级 |
| Rhapsody.Computation.DataGenerator       | 与目录同名 | 参考工程 |
| Rhapsody.Computation.DepthJumpCorrection | 与目录同名 | 本次升级 |
| Rhapsody.Computation.Flowback            | 与目录同名 | 本次升级 |
| Rhapsody.Computation.HydraulicsTransient | 与目录同名 | 本次升级 |
| rhapsody.computation.killsheet           | 与目录同名 | 本次升级 |
| Rhapsody.Computation.OperationKpi        | 与目录同名 | 本次升级 |
| Rhapsody.Computation.PackOff             | 与目录同名 | 本次升级 |
| Rhapsody.Computation.ProceduralAdherence | 与目录同名 | 本次升级 |
| Rhapsody.Computation.Risk                | 与目录同名 | 本次升级 |
| Rhapsody.Computation.RtRheology          | 与目录同名 | 本次升级 |
| Rhapsody.Computation.TndBroomstick       | 与目录同名 | 本次升级 |
| Rhapsody.Computation.Udf                 | 与目录同名 | 本次升级 |
| Rhapsody.Computation.WellBalanceRisks    | 与目录同名 | 本次升级 |
| Rhapsody.Service.ActorDirector           | 与目录同名 | 参考工程 |
| Rhapsody.Service.DrillingKpi             | 与目录同名 | 本次升级 |
| Rhapsody.Service.PressureMonitoring      | 与目录同名 | 本次升级 |
| Rhapsody.Service.StreamSampling          | 与目录同名 | 参考工程 |


### Actor和 Azure DevOps的Pipeline的对应关系

[Service和ADO Pipeline对应关系](./doc/rhapsody-service-to-ado-pipeline-mapping.md)

### Pipeline

| 目录                 | Repository | 说明                           |
| -------------------- | ---------- | ------------------------------ |
| CD                   | 与目录同名 | 公共Pipeline模板所使用的脚本   |
| rcis-devops-template | 与目录同名 | 每个项目使用的公共Pipeline模板 |

### Shared

| 目录                                           | Repository | 说明 |
| ---------------------------------------------- | ---------- | ---- |
| Rhapsody.Library.ComputationDaprAdapter        |            |      |
| Shared.Library.Computation.Common              |            |      |
| Rhapsody.Algorithm.ChannelProjection           |            |      |
| Shared.Algorithm.CementingHydraulics           |            |      |
| Shared.Algorithm.CoreComputation               |            |      |
| Rhapsody.Algorithm.DataGenerator               |            |      |
| Rhapsody.Algorithm.DepthJumpCorrection         |            |      |
| Shared.Algorithm.Flowback                      |            |      |
| Shared.Algorithm.HydraulicsTransientSimulation |            |      |
| Shared.Algorithm.KillSheet                     |            |      |
| Shared.Algorithm.OperationKpi                  |            |      |
| Shared.Algorithm.PackOff                       |            |      |
| Shared.Algorithm.ParameterAdherence            |            |      |
| Shared.Algorithm.PressureMonitoring            |            |      |
| Shared.Algorithm.RtRheology                    |            |      |
| Shared.Algorithm.TnDBroomstick                 |            |      |
| Shared.Library.WellBalanceRisks                |            |      |
| Rhapsody.Algorithm.Udf                         |            |      |
| Shared.Library.DrillingKpi                     |            |      |

- `../Rhapsody.Computation.DataGenerator/` — 已经改造完的Actor。用途：参考
- `../Rhapsody.Computation.DataGenerator.Master/` — 改造前的Actor。用途：参考
- `../Rhapsody.Service.DrillingKpi/` — 已经改造完的Actor。用途：参考
- `../Rhapsody.Service.DrillingKpi-Master/` — 改造前的Actor。用途：参考
- `../Shared.Library.DrillingKpi` — `Rhapsody.Service.DrillingKpi所依赖 数据结构。用途：参考
- `../Rhapsody.Computation.HydraulicsTransient/` — 待改造的的Actor以及Stateless Work
- `../Rhapsody.Computation.HydraulicsTransient-master/` — 改造前的Actor。用途：参考
- `../Rhapsody.Library.ComputationDaprAdapter/` - Actor依赖的底层包。用途：参考
- `../Core.Service.FileExportManager/` - Stateless Work的样例。用途：参考
- `../Pipeline/rcis-devops-template` - Pipeline底层包。用途：参考

## 升级 Pipeline 状态（ADO）

- **脚本**：`scripts/get-upgrade-pipeline-status.ps1` — 查询 **Prism** 项目中本次升级相关 Pipeline 在指定分支（默认 `refs/heads/dapr`）上的最近一次构建，输出 **构建结果** 与 **最后 Stage 日志** 链接；定义列表见 `scripts/upgrade-pipeline-definitions.json`（与 `doc/rhapsody-service-to-ado-pipeline-mapping.md` 对齐）。
- **认证（无 PAT）**：先执行 `az login`（AAD），脚本通过 `az account get-access-token --resource 499b84ac-1321-4277-86b9-215fbc768055` 获取 Azure DevOps 访问令牌。
- **Cursor 说明**：`.cursor/skills/prism-ado-pipeline-status/SKILL.md`。

## 代码要求

- 所有文本文件的换行必须符合Windows的CR/LF要求。
- 每个C#工程，尽量使用GlobalUsings.cs，减少每个C#文件中的using。

## 文档要求

- 格式均为Markdown文档
- Markdown文档需要符合markdownlint要求
