# 任务描述

需要编写一个标准流程，用于后续每一个task的引用。

## 流程目标

这个流程的目标是编写一个文本文档，描述从ServiceFabric的Actor升级到Dapr Actor。

- 这个任务文档为./tasks/upgrade-plan.md
- 任务最终的目标是升级参考工程../Rhapsody.Service.DrillingKpi项目

任务流程输入信息包含以下内容：

- 待升级的工程（repo）目录
- 目标版本（最终体现在SharedAssemblyInfo.cs中）

这个应该包含以下工作内容：

- 解决方案转换为slnx，去掉不兼容的Windows Service Fabric
- 包引用参考Rhapsody.Service.DrillingKpi
- 需要编写Dockerfile
- 需要参考环境变量注入
- 需要编写deploy中的helm chart
- 需要考虑版本信息体现在SharedAssemblyInfo中，以及nuspec中的一致性
- 如何清理工程和文件，删除不需要Service Fabric工程

验收条件：

- 编译通过
- AssemblyVersion和nuspec一致
- nuget可以打包(本地有nuget.exe)，并且解包验证名称、版本和目录
  - 主nuget什么样子，且保证包含代码和deploy。deploy是独立目录
  - IntegrationTests什么样子
- 单元测试和集成测试通过
- 本地有dapr.yaml
- 有本地dockerfile，可以build
- 使用values文件输出helm template，进行验证（与../Rhapsody.Service.DrillingKpi比较）
  