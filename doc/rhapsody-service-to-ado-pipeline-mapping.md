<!-- markdownlint-disable-file MD013 MD060 -->

# Rhapsody.Service.* 与 Prism ADO Pipeline 映射

## 说明

- **组织 / 项目**：`slb1-swt` / **Prism**
- **数据来源**：Azure DevOps Build 定义（`\rhapsody` 路径及按名称查询），查询时间以仓库内文档维护时点为准。
- **命名习惯**：本地/文档中的 **`Rhapsody.Service.*`**（含 Actor 仓库）在 ADO 中多数对应 **`Rhapsody.Computation.*`** 的 Pipeline；**DrillingKpi** 仍使用 **`Rhapsody.Service.DrillingKpi`**。少数 Pipeline 在 ADO 中为小写 **`rhapsody.computation.*`**。

## 主映射表

| 服务 / 仓库（常用称呼）              | ADO Pipeline 名称                        | Definition ID | Pipeline 链接                                                          |
| ------------------------------------ | ---------------------------------------- | ------------- | ---------------------------------------------------------------------- |
| Rhapsody.Service.DrillingKpi         | Rhapsody.Service.DrillingKpi             | 15814         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15814) |
| Rhapsody.Service.ChannelProjection   | Rhapsody.Computation.ChannelProjection   | 16279         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=16279) |
| Rhapsody.Service.HydraulicsTransient | Rhapsody.Computation.HydraulicsTransient | 21265         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=21265) |
| Rhapsody.Service.DepthJumpCorrection | Rhapsody.Computation.DepthJumpCorrection | 28565         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=28565) |
| Rhapsody.Service.RtRheology          | Rhapsody.Computation.RtRheology          | 30676         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=30676) |
| Rhapsody.Service.WellBalanceRisks    | Rhapsody.Computation.WellBalanceRisks    | 15950         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15950) |
| Rhapsody.Service.TndBroomstick       | Rhapsody.Computation.TnDBroomstick       | 16278         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=16278) |
| Rhapsody.Service.PressureMonitoring  | rhapsody.computation.pressuremonitoring  | 34094         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=34094) |
| Rhapsody.Service.Udf                 | Rhapsody.Computation.Udf                 | 19674         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=19674) |
| Rhapsody.Service.Flowback            | Rhapsody.Computation.Flowback            | 17736         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=17736) |
| Rhapsody.Service.Killsheet           | rhapsody.computation.killsheet           | 33868         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=33868) |
| Rhapsody.Service.Operationkpi        | Rhapsody.Computation.OperationKpi        | 24402         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=24402) |
| Rhapsody.Service.ProceduralAdherence | Rhapsody.Computation.ProceduralAdherence | 18561         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=18561) |
| Rhapsody.Service.Risk                | Rhapsody.Computation.Risk                | 20447         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=20447) |
| Rhapsody.Service.PackOff             | Rhapsody.Computation.PackOff             | 28971         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=28971) |

## Shared 算法仓库

| 仓库 / 本地目录名                              | ADO Pipeline 名称                              | Definition ID | Pipeline 链接                                                          |
| ---------------------------------------------- | ---------------------------------------------- | ------------- | ---------------------------------------------------------------------- |
| Rhapsody.Algorithm.ChannelProjection           | Rhapsody.Algorithm.ChannelProjection           | 16291         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=16291) |
| Rhapsody.Algorithm.DataGenerator               | Rhapsody.Algorithm.DataGenerator               | 16277         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=16277) |
| Rhapsody.Algorithm.DepthJumpCorrection         | Rhapsody.Algorithm.DepthJumpCorrection         | 28564         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=28564) |
| Rhapsody.Algorithm.Risk                        | Rhapsody.Algorithm.Risk                        | 20432         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=20432) |
| Rhapsody.Algorithm.Udf                         | Rhapsody.Algorithm.Udf                         | 19673         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=19673) |
| Rhapsody.Library.ComputationDaprAdapter        | Rhapsody.Library.ComputationDaprAdapter        | 34223         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=34223) |
| Shared.Algorithm.CementingHydraulics           | Shared.Algorithm.CementingHydraulics           | 31225         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=31225) |
| Shared.Algorithm.CoreComputation               | Shared.Algorithm.CoreComputation               | 15842         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15842) |
| Shared.Algorithm.Flowback                      | Shared.Algorithm.Flowback                      | 17720         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=17720) |
| Shared.Algorithm.HydraulicsTransientSimulation | Shared.Algorithm.HydraulicsTransientSimulation | 21279         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=21279) |
| Shared.Algorithm.KillSheet                     | Shared.Algorithm.KillSheet                     | 33817         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=33817) |
| Shared.Algorithm.OperationKpi                  | Shared.Algorithm.OperationKpi                  | 24414         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=24414) |
| Shared.Algorithm.PackOff                       | Shared.Algorithm.PackOff                       | 28963         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=28963) |
| Shared.Algorithm.ParameterAdherence            | Shared.Algorithm.ParameterAdherence            | 18533         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=18533) |
| Shared.Algorithm.PressureMonitoring            | Shared.Algorithm.PressureMonitoring            | 33998         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=33998) |
| Shared.Algorithm.RtRheology                    | Shared.Algorithm.RtRheology                    | 30428         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=30428) |
| Shared.Algorithm.TnDBroomstick                 | Shared.Algorithm.TnDBroomstick                 | 15482         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15482) |
| Shared.Library.Computation.Common              | Shared.Library.Computation.Common              | 15480         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15480) |
| Shared.Library.DrillingKpi                     | Shared.Library.DrillingKpi                     | 15851         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15851) |
| Shared.Library.WellBalanceRisks                | Shared.Library.WellBalanceRisks                | 15876         | [打开](https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15876) |

- **分支**：该 ADO Git 仓库当前**无** `dapr`；排队请使用 **`refs/heads/master`**（可用 `az repos ref list` 核对）。
- **模板参数**：与下文「启动 Pipeline 参数」一致，建议 **`CDPkgVersion=latest`**（`az pipelines run ... --parameters "CDPkgVersion=latest"`）。

## 批量查询最近一次构建（dapr）

可使用仓库脚本（AAD / `az login`，无 PAT）：`scripts/get-upgrade-pipeline-status.ps1`（定义列表见同目录 `upgrade-pipeline-definitions.json`）。

## Pipeline 链接格式

将 `<ID>` 替换为上表中的 Definition ID：

```text
https://dev.azure.com/slb1-swt/Prism/_build?definitionId=<ID>
```

示例（DrillingKpi）：

```text
https://dev.azure.com/slb1-swt/Prism/_build?definitionId=15814
```

## 补充：同路径下的 Algorithm Pipeline（可选）

以下能力在 **`\rhapsody`** 下同时存在 **Algorithm** 与 **Computation** 两套定义；若只关心 Actor/Computation 镜像构建，通常以 **Computation** 一行（主映射表）为准。

| 能力                | Rhapsody.Algorithm.*（ID） | Rhapsody.Computation.*（主表） |
| ------------------- | -------------------------- | ------------------------------ |
| DepthJumpCorrection | 28564                      | 28565                          |
| Risk                | 20432                      | 20447                          |
| Udf                 | 19673                      | 19674                          |

## 启动Pipeline参数

启动Pipeline，都是选择dapr分支。然后参数设置如下：

| 参数名       | 值     | 说明 |
| ------------ | ------ | ---- |
| CDPkgVersion | latest |      |

## 备注

1. **ChannelProjectionActor / HydraulicsTransientActor**：ADO 中无同名 Pipeline，CI 对应 **Rhapsody.Computation.ChannelProjection**、**Rhapsody.Computation.HydraulicsTransient**。
2. **Killsheet**：Pipeline 名为全小写 **rhapsody.computation.killsheet**，且定义文件夹常为根路径 **`\`**，不一定落在 **`\rhapsody`** 下。
3. ID 若与 ADO 上不一致，以 DevOps 中 **Edit pipeline** 页面 URL 或 REST 返回为准。
