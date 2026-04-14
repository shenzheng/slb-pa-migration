# Rhapsody.Service.* 与 Prism ADO Pipeline 映射

## 说明

- **组织 / 项目**：`slb1-swt` / **Prism**
- **数据来源**：Azure DevOps Build 定义（`\rhapsody` 路径及按名称查询），查询时间以仓库内文档维护时点为准。
- **命名习惯**：本地/文档中的 **`Rhapsody.Service.*`**（含 Actor 仓库）在 ADO 中多数对应 **`Rhapsody.Computation.*`** 的 Pipeline；**DrillingKpi** 仍使用 **`Rhapsody.Service.DrillingKpi`**。少数 Pipeline 在 ADO 中为小写 **`rhapsody.computation.*`**。

## 主映射表

| 服务 / 仓库（常用称呼）              | ADO Pipeline 名称                        | Definition ID |
| ------------------------------------ | ---------------------------------------- | ------------- |
| Rhapsody.Service.DrillingKpi         | Rhapsody.Service.DrillingKpi             | 15814         |
| Rhapsody.Service.ChannelProjection   | Rhapsody.Computation.ChannelProjection   | 16279         |
| Rhapsody.Service.HydraulicsTransient | Rhapsody.Computation.HydraulicsTransient | 21265         |
| Rhapsody.Service.DepthJumpCorrection | Rhapsody.Computation.DepthJumpCorrection | 28565         |
| Rhapsody.Service.RtRheology          | Rhapsody.Computation.RtRheology          | 30676         |
| Rhapsody.Service.WellBalanceRisks    | Rhapsody.Computation.WellBalanceRisks    | 15950         |
| Rhapsody.Service.TndBroomstick       | Rhapsody.Computation.TnDBroomstick       | 16278         |
| Rhapsody.Service.PressureMonitoring  | rhapsody.computation.pressuremonitoring  | 34094         |
| Rhapsody.Service.Udf                 | Rhapsody.Computation.Udf                 | 19674         |
| Rhapsody.Service.Flowback            | Rhapsody.Computation.Flowback            | 17736         |
| Rhapsody.Service.Killsheet           | rhapsody.computation.killsheet           | 33868         |
| Rhapsody.Service.Operationkpi        | Rhapsody.Computation.OperationKpi        | 24402         |
| Rhapsody.Service.ProceduralAdherence | Rhapsody.Computation.ProceduralAdherence | 18561         |
| Rhapsody.Service.Risk                | Rhapsody.Computation.Risk                | 20447         |
| Rhapsody.Service.PackOff             | Rhapsody.Computation.PackOff             | 28971         |

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
