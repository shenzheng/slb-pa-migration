# Service Fabric Actor 升级到 Dapr Actor 标准流程

## 1. 目标

本文档用于指导 Prism 算法服务从 Service Fabric Actor 升级到 Dapr Actor，并作为后续同类 task 的标准引用流程。

本文档以 `../Rhapsody.Service.DrillingKpi` 为目标结构参考，以 `../Rhapsody.Computation.HydraulicsTransient` 为待规范化参考，统一按以下目标落地：

- .NET 10
- `PlatformTarget` 为 `x64`
- Actor 模式迁移到 Dapr Actor
- 后台服务迁移到 ASP.NET Core 服务
- 产出 Docker、Helm Chart、nuspec、本地 `dapr.yaml`

## 2. 输入参数

升级流程只接收以下两个输入参数：

| 参数 | 说明 | 示例 |
| --- | --- | --- |
| `RepoPath` | 待升级工程根目录 | `../Rhapsody.Service.DrillingKpi` |
| `ProviderName` | 日志配置中的 ProviderName，尾号为主版本号来源 | `Slb.Prism.Rhapsody.Service.DrillingKpi-3` |

### 2.1 ProviderName 规则

- `ProviderName` 必须写入 `appsettings.json` 的 `LoggerSetup.EnricherConfiguration.Properties.ProviderName`
- `ProviderName` 最后一个连字符后的数字视为主版本号
- 例如 `Slb.Prism.Rhapsody.Service.DrillingKpi-3` 的主版本号是 `3`
- 主版本号用于更新 `SharedAssemblyInfo.cs`
- 主版本号也必须同步到主 `.nuspec` 和 `IntegrationTests` 的 `.nuspec`

## 3. 适用范围

本文档适用于以下两类升级场景：

- 纯 Actor 服务升级
- Actor + 可选后台 Worker 的组合升级

如果旧工程中包含 Stateless Worker，则 Worker 作为可选分支处理，迁移方式参考 `../Core.Service.FileExportManager` 和 `../Rhapsody.Computation.HydraulicsTransient/deploy/charts/worker`

## 4. 目标输出结构

升级完成后，工程应至少具备以下结构：

- `.slnx` 解决方案文件
- Actor 宿主 ASP.NET Core Web 工程
- 可选的 Worker ASP.NET Core 工程
- Contract 工程
- `UnitTests`
- `IntegrationTests`
- `SharedAssemblyInfo.cs`
- 主 `.nuspec`
- `IntegrationTests` 对应 `.nuspec`
- `Dockerfile`
- `DockerfileLocal`
- `dapr.yaml`
- `deploy/`

服务命名统一从 `Slb.Prism.Rhapsody.Computation.*` 调整为 `Slb.Prism.Rhapsody.Service.*`

## 5. 升级步骤

### 5.1 基线盘点

升级前先盘点旧工程，确认以下内容：

- 解决方案文件，包含 `.sln`、`.slnx`
- Service Fabric 相关工程，例如 `*.sfproj`
- `ApplicationManifest.xml`、`ServiceManifest.xml`
- Service Fabric 应用包目录，例如 `ApplicationPackageRoot`
- Actor 工程
- Worker 工程
- Contract 工程
- 单元测试和集成测试工程
- `SharedAssemblyInfo.cs`
- `.nuspec`
- `Dockerfile`、部署脚本、CI/CD 文件

输出一份清单，标记：

- 必须保留的工程
- 必须迁移的工程
- 必须删除的 Service Fabric 资产

### 5.2 解决方案转换为 `.slnx`

- 将解决方案统一转换为 `.slnx`
- 平台统一为 `x64`
- 仅保留迁移后仍需要的工程

推荐保留的项目类型：

- Actor 宿主工程
- Contract 工程
- `UnitTests`
- `IntegrationTests`
- 可选 Worker 工程

需要从解决方案中移除的内容：

- Service Fabric 应用工程
- 仅用于旧部署模型的工程
- 失效的打包或发布工程

### 5.3 清理 Service Fabric 资产

从 repo 中删除或移除以下内容：

- `*.sfproj`
- `ApplicationManifest.xml`
- `ServiceManifest.xml`
- `ApplicationPackageRoot`
- Service Fabric publish profiles
- Service Fabric 专用参数文件
- Service Fabric 专用脚本
- 不再使用的 Windows Service Fabric 依赖包

同时检查并清理以下残留：

- 工程文件中的 Service Fabric 包引用
- 启动代码中的 Service Fabric 宿主逻辑
- 仅对旧集群部署有效的配置项
- 不再使用的旧目录和中间资源

### 5.4 Actor 宿主迁移到 ASP.NET Core + Dapr Actor

Actor 宿主统一迁移为 ASP.NET Core Web 项目。

关键要求如下：

- 目标框架统一为 `net10.0`
- `PlatformTarget` 为 `x64`
- 项目 SDK 使用 `Microsoft.NET.Sdk.Web`
- `GenerateAssemblyInfo` 设为 `false`
- 通过链接方式引用根目录 `SharedAssemblyInfo.cs`
- 包引用优先参考 `../Rhapsody.Service.DrillingKpi`
- Dapr Actor 宿主能力参考 `../Rhapsody.Library.ComputationDaprAdapter`

`Program.cs` 统一采用以下模式：

```csharp
using Slb.Prism.Rhapsody.Library.ComputationDaprAdapter.Extensions;

var builder = WebApplication.CreateBuilder(args);
var app = builder.BuildApplication<YourActor>();
app.Run();
```

迁移时需要同步处理：

- 程序集名称
- RootNamespace
- Actor 类型命名
- 服务名
- 日志中的 `ProviderName`
- 所有 `Slb.Prism.Rhapsody.Computation.*` 到 `Slb.Prism.Rhapsody.Service.*` 的命名迁移

### 5.5 包引用和公共依赖整理

包引用基线以 `../Rhapsody.Service.DrillingKpi` 为准，迁移时至少检查以下内容：

- `Newtonsoft.Json`
- `Slb.Prism.Rhapsody.Library.ComputationDaprAdapter`
- 算法共享包
- Contract 工程引用

整理要求如下：

- 删除 Service Fabric 相关包
- 增加或更新 Dapr Actor 所需包
- 核对算法包是否与目标服务兼容
- 保持 Contract 工程引用关系正确
- 每个 C# 工程尽量使用 `GlobalUsings.cs`

### 5.6 Worker 迁移分支

如果旧工程包含 Stateless Worker，则按 ASP.NET Core 后台服务迁移。

迁移要求如下：

- Worker 独立为 ASP.NET Core 项目
- 启动方式参考 `../Core.Service.FileExportManager`
- 如果需要独立部署，则在 Helm 中提供 `deploy/charts/worker`
- Worker 的环境变量、镜像名、资源配置独立维护
- Worker 是否保留 `service` 暴露能力，按实际运行模型确认

如果目标项目没有 Worker，可以省略本节对应产物。

### 5.7 配置文件调整

`appsettings.json` 必须包含标准 logging 配置，并写入输入参数 `ProviderName`。

最少需要包含以下结构：

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information"
    }
  },
  "LoggerSetup": {
    "LogLevelConfiguration": {
      "DefaultLevel": "Trace",
      "NamespaceLevels": {
        "Microsoft": "Warning",
        "System": "Error"
      }
    },
    "SinkConfiguration": {
      "Sinks": [
        {
          "Name": "Console",
          "Args": {
            "TextFormatter": "Serilog.Formatting.Elasticsearch.ElasticsearchJsonFormatter, Serilog.Formatting.Elasticsearch"
          }
        }
      ]
    },
    "EnricherConfiguration": {
      "Properties": {
        "ProviderName": "<ProviderName>"
      }
    }
  },
  "AllowedHosts": "*"
}
```

如果旧工程存在额外业务配置，例如批量参数、RabbitMQ 或状态存储配置，则在保留原有业务语义的前提下迁移到新的宿主配置体系。

### 5.8 版本信息同步

版本信息不再单独输入，而是从 `ProviderName` 提取主版本号。

处理规则如下：

- `ProviderName=Slb.Prism.Rhapsody.Service.DrillingKpi-3` 时，主版本号为 `3`
- `SharedAssemblyInfo.cs` 中至少要更新：
  - `AssemblyVersion`
  - `AssemblyFileVersion`
  - `AssemblyInformationalVersion`
- 主 `.nuspec` 的 `<version>` 必须与程序集版本一致
- `IntegrationTests` 的 `.nuspec` 版本也必须同步

建议统一采用四段式版本：

- `AssemblyVersion("3.0")`
- `AssemblyFileVersion("3.0.0.0")`
- `AssemblyInformationalVersion("3.0.0.0")`
- `.nuspec` `<version>3.0.0.0</version>`

### 5.9 Docker 产物

需要同时提供两个 Docker 文件：

- `Dockerfile`
- `DockerfileLocal`

要求如下：

- `Dockerfile` 用于正式构建和 CI/CD
- `Dockerfile` 参考 `../Rhapsody.Service.DrillingKpi`
- `Dockerfile` 不要求在本地完成镜像构建验证
- `DockerfileLocal` 用于本地打包验证
- `DockerfileLocal` 必须支持本地 `docker build`

`Dockerfile` 需要覆盖以下能力：

- restore
- build
- publish
- 正式镜像入口
- 企业证书注入
- NuGet 源注入

`DockerfileLocal` 需要覆盖以下能力：

- 本地 restore
- 本地 build 或 publish
- 本地镜像入口
- 尽量减少对企业 CI 环境变量的依赖
- 优先支持对本地发布产物目录执行 `docker build`，避免直接以 repo 根目录作为上下文时因产物、packages 或历史文件过多导致超时

### 5.10 本地 Dapr 调试文件

repo 根目录下必须提供 `dapr.yaml`。

要求如下：

- `resourcesPath` 指向本地 Dapr 组件目录
- `apps` 中声明 Actor 宿主
- 设置本地调试端口
- 设置本地环境变量
- `command` 指向实际 Actor 宿主项目

至少覆盖以下环境变量：

- `env`
- `consulUri`
- `ASPNETCORE_ENVIRONMENT`
- `DOTNET_ENVIRONMENT`

如服务依赖 Dapr state store 或其他组件，则增加相应变量和本地组件定义。

### 5.11 Helm Chart

必须提供 `deploy/` 目录，并保证可以通过 `helm template` 渲染。

基础结构如下：

```text
deploy/
  Chart.yaml
  values.yaml
  templates/
```

如果包含 Worker，则扩展为：

```text
deploy/
  Chart.yaml
  values.yaml
  templates/
  charts/
    worker/
      Chart.yaml
      values.yaml
      templates/
```

Helm 迁移要求如下：

- 主 chart 负责 Actor 宿主部署
- 有 Worker 时，Worker 使用独立子 chart
- values 文件中维护镜像、环境变量、副本数、资源限制等参数
- 模板中包含 Dapr annotations
- 模板支持从 `secretRef` 注入环境变量
- 模板可根据需要支持 `serviceaccount`、`hpa`、`service`

渲染结果需与 `../Rhapsody.Service.DrillingKpi` 的结构风格保持一致，重点检查：

- Deployment 结构
- Dapr annotations
- 环境变量注入方式
- 镜像命名方式
- Worker 子 chart 组织方式

### 5.12 nuspec 打包

必须保留 nuspec 打包能力，因为项目存在集成测试和交付要求。

主包要求如下：

- 包含 `SharedAssemblyInfo.cs`
- 包含完整 `deploy/**/*.*`
- Actor 或 ASP.NET Core 服务升级到 Helm 部署时，主包必须包含 `CustomizeValues.ps1`
- `CustomizeValues.ps1` 即使只是空实现也不能省略；缺失时底层 CD 可能无法识别包内 `deploy`，并回退到默认 `deployTemplate`
- `deploy` 在 NuGet 包中保持独立目录

`IntegrationTests` 包要求如下：

- 独立生成 `.nuspec`
- 打包 `IntegrationTests` 的发布或构建产物
- 解包后应能看到测试二进制输出目录

### 5.13 CI/CD 检查

CI/CD 文件可参考 `../Pipeline/rcis-devops-template` 以及现有服务样例。

升级时至少检查以下内容：

- `pipeline.json` 的结构和关键字段对齐 `../Rhapsody.Service.DrillingKpi`，至少包括：
  - `type`
  - `name`
  - `workingBranch`
  - `buildAgent.template`
  - `compile.platform`
  - `pkg.nuspecPath`
  - `pkg.nuspecIntPath`
  - `codescan.sourceDirs`
  - `buildAgent.queue`
  - `codescan.excludeDirs`
  - `pipelineTemplateVersion`
- 解决方案文件名是否已切换为 `.slnx`
- 构建入口是否指向新项目
- Docker 构建文件名是否正确
- nuspec 打包路径是否正确
- Helm Chart 路径是否正确
- 测试项目路径是否正确
- `azure-pipelines-ci.yml` 顶层 `extends` 模板是否已从 `tpl-ServiceFabricCloud.yml` 切换为 `tpl-InternalImageDotNetCloud.yml`
- 不能只修改 `pipeline.json` 的 `type`；如果 `azure-pipelines-ci.yml` 仍引用 `ServiceFabricCloud` 模板，则不会生成 `Image` stage，也不会执行镜像打包
- 必须确认部署阶段实际消费 NuGet 包内的 `deploy/` Helm Chart，而不是回退到底层默认 `deployTemplate`
- 若服务使用 Helm 部署，需补齐并打包 `CustomizeValues.ps1`，避免底层 CI/CD 因识别失败而忽略包内 `deploy/`

## 6. 清理完成标准

升级完成后，repo 中不应再残留以下内容：

- `*.sfproj`
- `ApplicationManifest.xml`
- `ServiceManifest.xml`
- `ApplicationPackageRoot`
- 旧 Service Fabric 发布脚本
- 无人使用的旧部署目录
- 无效的 Service Fabric 依赖引用
- 旧命名下不再使用的工程或文件

同时应确认以下内容：

- `.slnx` 只包含有效项目
- 所有服务命名已切换为 `Slb.Prism.Rhapsody.Service.*`
- Docker、Helm、dapr、nuspec 产物齐全
- 测试工程仍可编译和执行

## 7. 标准验收顺序

建议按以下顺序执行验收。

### 7.1 编译

```powershell
dotnet restore
dotnet build -c Release
```

验收要求：

- 所有目标工程编译通过
- 无残留 Service Fabric 依赖导致的编译错误

### 7.2 测试

```powershell
dotnet test -c Release
```

验收要求：

- 单元测试通过
- 集成测试通过

### 7.3 版本一致性检查

检查以下文件中的版本是否一致：

- `SharedAssemblyInfo.cs`
- 主 `.nuspec`
- `IntegrationTests` `.nuspec`

验收要求：

- 主版本来自 `ProviderName` 尾号
- `AssemblyVersion`、`AssemblyFileVersion`、`AssemblyInformationalVersion` 与 `.nuspec` 一致

### 7.4 NuGet 打包与解包验证

```powershell
nuget.exe pack .\Slb.Prism.Rhapsody.Service.XXX.nuspec
nuget.exe pack .\IntegrationTests\Slb.Prism.Rhapsody.Service.XXX.IntegrationTests.nuspec
```

解包后重点检查：

- 主包名称正确
- 主包版本正确
- 主包包含 `SharedAssemblyInfo.cs`
- 主包包含 `deploy/`
- 主包包含必要脚本
- 主包必须包含 `CustomizeValues.ps1`
- `deploy` 为独立目录
- 解包后需确认部署链路使用的是包内 `deploy/`，而不是默认 `deployTemplate`
- `IntegrationTests` 包名称正确
- `IntegrationTests` 包版本正确
- `IntegrationTests` 包中存在测试输出目录

### 7.5 Dapr 本地调试文件检查

验收要求：

- repo 根目录存在 `dapr.yaml`
- 本地组件目录可用
- Actor 项目路径正确
- 本地环境变量完整

### 7.6 Docker 本地打包验证

```powershell
docker build -f .\DockerfileLocal -t local-test .
```

如 repo 根目录上下文较大，推荐先完成本地发布，再切换到发布产物目录作为构建上下文执行：

```powershell
dotnet publish .\YourActorProject\YourActorProject.csproj -c Release -o .\artifacts\publish\actor
docker build -f ..\..\DockerfileLocal -t local-test --build-arg APP_DLL=YourServiceActor.dll .\artifacts\publish\actor
```

验收要求：

- `DockerfileLocal` 可本地成功构建

说明：

- `Dockerfile` 仅要求用于正式构建和 CI/CD
- 本地验证以 `DockerfileLocal` 为准
- 当仓库根目录上下文过大时，应优先采用“发布产物目录 + 根目录 `DockerfileLocal`”的方式完成本地验证

### 7.7 Helm 渲染验证

```powershell
helm template local-test .\deploy -f .\deploy\values.yaml
```

如存在本地 values 文件，可继续执行：

```powershell
helm template local-test .\deploy -f .\deploy\values.yaml -f .\deploy\values.local.k8s.yaml
```

验收要求：

- 模板渲染成功
- 关键资源结构正确
- 与 `../Rhapsody.Service.DrillingKpi` 的输出结构一致或等价

## 8. 验收清单

- 编译通过
- 单元测试通过
- 集成测试通过
- `ProviderName` 推导出的主版本与 `SharedAssemblyInfo.cs` 一致
- `ProviderName` 推导出的主版本与主 `.nuspec` 一致
- `ProviderName` 推导出的主版本与 `IntegrationTests` `.nuspec` 一致
- `nuget.exe pack` 成功
- 主 NuGet 包结构正确
- `IntegrationTests` NuGet 包结构正确
- 存在本地 `dapr.yaml`
- 存在 `Dockerfile`
- 存在 `DockerfileLocal`
- `DockerfileLocal` 可本地 build
- `helm template` 渲染成功
- Service Fabric 旧资产已清理

## 9. 参考工程

- `../Rhapsody.Service.DrillingKpi`
- `../Rhapsody.Computation.HydraulicsTransient`
- `../Rhapsody.Library.ComputationDaprAdapter`
- `../Core.Service.FileExportManager`
- `../Pipeline/rcis-devops-template`

## 10. 输出要求

后续每个具体升级 task 在引用本文档时，至少应显式给出以下信息：

- 待升级 repo 路径
- `ProviderName`
- 是否包含 Worker
- 是否需要保留 Contract 工程
- 主包和 `IntegrationTests` 包名称

执行具体任务时，最终交付物应满足：

- 工程已完成从 Service Fabric Actor 到 Dapr Actor 的迁移
- 版本与打包信息一致
- 本地调试、容器构建、Helm 渲染、测试执行均可验证
