# 任务描述

从日志和Pipeline中整理出单一Actor和Actor+Worker的执行有什么不一样。

背景资料

单一Actor

- 以工程`./Rhapsody.Computation.RtRheology`为参考，其入口为`azure-pipelines-ci.yml`，作为单一Actor参考
- `./Rhapsody.Computation.RtRheology_15507955`是一次成功部署日志

Actor + Worker

- `../Rhapsody.Computation.HydraulicsTransient/` — 为Actor + Worker。pipeline入口和单一Actor类似
- `./Rhapsody.Computation.HydraulicsTransient_15458693`是一次成功部署日志

通用模板

- `../Pipeline/rcis-devops-template`是实际的流程

希望输出的文档，在

- 这两类工程在pipeline中采用的dockerfile名称是不同的，不知道判别依据是什么
- 还有什么导致了pipeline的差异性，差异是什么
- ./sample-doc目录下，补充进文档pipeline-stages.md
