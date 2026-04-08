# 任务描述

从日志和Pipeline中整理一篇详细的Markdown文档，用于描述Azure CI/CD的Pipeline的每个Stage所需要的数据以及产出物

背景资料

- 以工程`./Rhapsody.Computation.RtRheology`为参考，其入口为`azure-pipelines-ci.yml`
- `../Pipeline/rcis-devops-template`是实际的流程
- `./Rhapsody.Computation.RtRheology_15507955`是一次成功部署日志

希望输出的文档，在

- ./sample-doc目录下，命名为pipeline-stages.md
- 步骤描述是分层级的，最细颗粒度到stage级别
- 从源代码的repository开始，列出每个stage的所依赖的源代码中的部分
  - 代码不用考虑列出，但是什么dockerfile，nuspec，pipeline.json是需要的
  - 依赖别的stage产出物也必须标出
- 也要列出每个stage是输出了什么
- 命名要严谨，前后能对得上
