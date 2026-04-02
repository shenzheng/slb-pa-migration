任务名称，将Rhapsody.Computation.ChannelProjection工程项目转换为.Net 10的Dapr项目

仿照../Rhapsody.Service.DrillingKpi项目，将这个使用Windows Service Fabric的项目转换为Dapr Actor应用。

- 解决方案转换为slnx，去掉不兼容的Windows Service Fabric
- 包引用参考Rhapsody.Service.DrillingKpi
- 需要编写Dockerfile
- 需要参考环境变量注入
- 需要编写deploy中的helm chart

验收条件：

- 编译通过
- 单元测试和集成测试通过
- 本地有dapr.yaml
- 有本地dockerfile，可以build
- 使用values文件输出helm template，进行验证（与../Rhapsody.Service.DrillingKpi比较）
  