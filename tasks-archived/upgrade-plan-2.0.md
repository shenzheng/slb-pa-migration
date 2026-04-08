# Service Fabric Actor 升级到 Dapr Actor 标准流程 2.0

## 1. 文档目标

本文档用于指导 Prism 算法服务从 Service Fabric Actor 升级到 Dapr Actor，并作为后续同类 task 的标准引用流程。

本文档是通用升级标准，不绑定某一个具体 repo 的实施记录。执行具体任务时，应先从上下文提取参数，再按本文档的阶段顺序逐步迁移、逐步验证、逐步签入。

由于目录结构可能变化，本文档不依赖固定的外部参考文件路径。对于短小且稳定的配置、入口与校验模式，直接在文档中给出内嵌示例；对于较大的实现，仅说明“按用途寻找同类已改造样例”，不把某个固定目录写成前置依赖。

升级完成后的目标状态如下：

- 服务运行时升级到 .NET 10
- `PlatformTarget` 统一为 `x64`
- Actor 模式迁移到 Dapr Actor
- 后台服务迁移到 ASP.NET Core 服务
- 服务名称从 `Slb.Prism.Rhapsody.Computation.*` 迁移为 `Slb.Prism.Rhapsody.Service.*`
- 交付物包含 Docker、Helm Chart、nuspec、本地 `dapr.yaml`
- CI/CD 切换到镜像构建与 Helm 部署链路

## 2. 输入与上下文提取规则

### 2.1 必需输入

升级流程只接收以下输入信息：

| 参数           | 说明                                          | 示例                                       |
| -------------- | --------------------------------------------- | ------------------------------------------ |
| `RepoPath`     | 待升级工程根目录                              | `../Rhapsody.Service.DrillingKpi`          |
| `ProviderName` | 日志配置中的 ProviderName，尾号为主版本号来源 | `Slb.Prism.Rhapsody.Service.DrillingKpi-3` |
| `PipelineName` | Azure DevOps 中需要核对或执行的目标 Pipeline 名称 | `Rhapsody.Service.DrillingKpi-CI`          |

### 2.2 从上下文提取的标准参数

执行具体升级任务前，先从 repo 当前内容中提取以下上下文参数：

| 参数                         | 说明                   | 提取规则                                              |
| ---------------------------- | ---------------------- | ----------------------------------------------------- |
| `RepoPath`                   | 仓库根目录             | 来自任务输入                                          |
| `RepositoryName`             | 仓库名称               | 取 `RepoPath` 最后一级目录名                          |
| `ProviderName`               | 日志 ProviderName      | 来自任务输入                                          |
| `PipelineName`               | 目标 Pipeline 名称     | 优先来自任务输入；若缺失，可从现有 pipeline 配置或 Azure DevOps 记录中确认 |
| `MajorVersion`               | 主版本号               | 取 `ProviderName` 最后一个连字符后的数字              |
| `SolutionPath`               | 主解决方案路径         | 优先选择 repo 根目录主 `.slnx`，否则从 `.sln` 转换    |
| `ActorProjectPath`           | Actor 宿主工程路径     | 从旧 Actor 工程或目标 ASP.NET Core Actor 宿主工程定位 |
| `WorkerProjectPath`          | Worker 工程路径        | 若存在 Stateless Worker，则标记；不存在则留空         |
| `ContractProjectPath`        | Contract 工程路径      | 若存在 Contract 工程，则标记；不存在则留空            |
| `MainNuspecPath`             | 主包 nuspec 路径       | repo 根目录主服务 `.nuspec`                           |
| `IntegrationTestsNuspecPath` | 集成测试包 nuspec 路径 | `IntegrationTests` 目录下对应 `.nuspec`               |
| `MainPackageId`              | 主包 ID                | 从主 `.nuspec` 的 `<id>` 提取                         |
| `IntegrationTestsPackageId`  | 集成测试包 ID          | 从集成测试 `.nuspec` 的 `<id>` 提取                   |

### 2.3 ProviderName 与版本规则

- `ProviderName` 必须写入 `appsettings.json` 的 `LoggerSetup.EnricherConfiguration.Properties.ProviderName`
- `ProviderName` 最后一个连字符后的数字视为 `MajorVersion`
- `MajorVersion` 用于同步更新 `SharedAssemblyInfo.cs`
- `MajorVersion` 也必须同步到主 `.nuspec` 与 `IntegrationTests` `.nuspec`

建议统一采用如下版本格式：

- `AssemblyVersion("<MajorVersion>.0")`
- `AssemblyFileVersion("<MajorVersion>.0.0.0")`
- `AssemblyInformationalVersion("<MajorVersion>.0.0.0")`
- `.nuspec` `<version><MajorVersion>.0.0.0</version>`

### 2.4 参数化占位符

文档、模板说明和参考文件映射中统一使用以下占位符：

| 占位符                         | 含义                                            |
| ------------------------------ | ----------------------------------------------- |
| `<RepoPath>`                   | 目标 repo 根目录                                |
| `<RepositoryName>`             | 目标 repo 名称                                  |
| `<ProviderName>`               | 日志 ProviderName                               |
| `<PipelineName>`               | 目标 Pipeline 名称                              |
| `<MajorVersion>`               | 从 `ProviderName` 提取的主版本                  |
| `<SolutionPath>`               | 目标解决方案路径                                |
| `<ActorProjectPath>`           | Actor 宿主工程路径                              |
| `<ActorProjectName>`           | Actor 宿主工程名                                |
| `<WorkerProjectPath>`          | Worker 工程路径                                 |
| `<WorkerProjectName>`          | Worker 工程名                                   |
| `<ContractProjectPath>`        | Contract 工程路径                               |
| `<ServiceName>`                | 新服务名，格式为 `Slb.Prism.Rhapsody.Service.*` |
| `<MainNuspecPath>`             | 主包 nuspec 路径                                |
| `<IntegrationTestsNuspecPath>` | 集成测试包 nuspec 路径                          |
| `<MainPackageId>`              | 主包 ID                                         |
| `<IntegrationTestsPackageId>`  | 集成测试包 ID                                   |

## 3. 输出物清单

升级完成后，repo 应至少具备以下输出物：

- 主 `.slnx` 解决方案
- Actor 宿主 ASP.NET Core Web 工程
- 可选 Worker ASP.NET Core 工程
- 可选 Contract 工程
- `UnitTests`
- `IntegrationTests`
- `SharedAssemblyInfo.cs`
- 主 `.nuspec`
- `IntegrationTests` `.nuspec`
- `Dockerfile`
- `DockerfileLocal`
- `dapr.yaml`
- `deploy/`
- `pipeline.json`
- `azure-pipelines-ci.yml`
- 已确认名称的目标 Pipeline 记录
- `CustomizeValues.ps1`
- `scripts/normalize-crlf.ps1`

## 4. 分步骤升级流程

### 4.1 创建 `dapr` 分支

#### 要做什么

- 从目标 repo 当前 `master` 创建 `dapr` 分支
- 后续所有改造工作均在 `dapr` 分支上进行

#### 需要改哪些文件

- 本步骤不修改 repo 受版本控制的文件

#### 参考文件来自哪里

- 无文件参考

#### 检查条件

- 当前分支名称为 `dapr`
- `dapr` 分支起点来自当前 `master`

#### 验证逻辑

- 执行 `git branch --show-current`
- 执行 `git log --oneline master..HEAD`，确认没有意外历史

#### 单独签入要求

- 本步骤不需要代码提交
- 后续所有提交必须在 `dapr` 分支完成

### 4.2 基线盘点与迁移清单

#### 要做什么

- 盘点旧工程的解决方案、Actor、Worker、Contract、测试、打包、部署与 Service Fabric 资产
- 输出迁移清单，明确哪些资产保留、迁移、删除

#### 需要改哪些文件

- 本步骤通常不修改文件
- 如需形成盘点说明，可新增 Markdown 文档，但不是必须

#### 参考文件来自哪里

- 目标 repo 当前结构
- 同类已改造 Actor 服务
- 同类已改造 Worker 服务

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                                                       | 参考来源                          | 占位符参数                                                         |
| -------------------------------------------------------------- | --------------------------------- | ------------------------------------------------------------------ |
| `<SolutionPath>`                                               | 同类已改造服务的 `.slnx` 组织方式 | `<SolutionPath>`                                                   |
| `*.sfproj` / `ApplicationManifest.xml` / `ServiceManifest.xml` | 旧工程现状                        | `<RepoPath>`                                                       |
| Actor / Worker / Contract / Tests 工程                         | 旧工程现状                        | `<ActorProjectPath>` `<WorkerProjectPath>` `<ContractProjectPath>` |

#### 检查条件

- 已识别所有需要保留的工程
- 已识别所有 Service Fabric 专属资产
- 已确认是否存在 Worker 与 Contract

#### 验证逻辑

- 列出 repo 中的 `.sln`、`.slnx`、`*.csproj`、`*.sfproj`
- 列出 `ApplicationPackageRoot`、`PublishProfiles`、Manifest 文件

#### 单独签入要求

- 若本步骤未修改文件，则不提交
- 若新增盘点文档，则单独提交一次

### 4.3 解决方案与项目结构调整

#### 要做什么

- 将解决方案统一为 `.slnx`
- 保留迁移后仍需要的项目
- 从解决方案中移除不再使用的 Service Fabric 或旧部署项目
- 将 C# 项目目标框架切换到 `net10.0`
- 将 `Platform`和`PlatformTarget` 统一为 `x64`

#### 需要改哪些文件

- `<SolutionPath>`
- `*.csproj`
- 可选 `Directory.Build.props`
- 可选 `GlobalUsings.cs`

#### 参考文件来自哪里

- 同类已改造服务的 `.slnx` 结构
- 同类已改造 Actor 宿主工程文件
- 同类已改造 `Directory.Build.props`

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                                         | 参考来源                            | 占位符参数                                                |
| ------------------------------------------------ | ----------------------------------- | --------------------------------------------------------- |
| `<SolutionPath>`                                 | 同类已改造服务的 `.slnx` 组织方式   | `<SolutionPath>`                                          |
| `<ActorProjectPath>/<ActorProjectName>.csproj`   | 同类已改造 Actor 宿主工程文件       | `<ActorProjectPath>` `<ActorProjectName>` `<ServiceName>` |
| `<WorkerProjectPath>/<WorkerProjectName>.csproj` | 同类已改造 Worker 工程文件          | `<WorkerProjectPath>` `<WorkerProjectName>`               |
| `<ContractProjectPath>/*.csproj`                 | 目标 repo 内保留的 Contract 工程    | `<ContractProjectPath>`                                   |
| `GlobalUsings.cs`                                | 已改造工程的 `GlobalUsings.cs` 写法 | `<ActorProjectPath>` `<WorkerProjectPath>`                |

#### 内嵌示例

`Program.cs` 之外，项目文件至少应满足以下形态：

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <PlatformTarget>x64</PlatformTarget>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
  </PropertyGroup>

  <ItemGroup>
    <Compile Include="..\\SharedAssemblyInfo.cs" Link="Properties\\SharedAssemblyInfo.cs" />
  </ItemGroup>
</Project>
```

如仓库内已有统一公共配置，也可以把 `PlatformTarget` 等设置提升到 `Directory.Build.props`。

#### 检查条件

- 解决方案已切换到 `.slnx`
- 无效项目已从解决方案移除
- 目标项目框架为 `net10.0`
- `PlatformTarget` 为 `x64`
- `GlobalUsings.cs` 已尽量替代零散 `using`

#### 验证逻辑

- 执行 `dotnet sln <SolutionPath> list`
- 检查所有目标项目 `TargetFramework` 与 `PlatformTarget`
- 检查是否仍存在旧 `.sln` 被 CI 引用

#### 单独签入要求

- 本阶段完成且结构检查通过后，应立即单独提交一次，再进入下一阶段

### 4.4 Actor 宿主迁移到 ASP.NET Core + Dapr Actor

#### 要做什么

- 将 Actor 宿主迁移为 ASP.NET Core Web 项目
- 引入 Dapr Actor 宿主能力
- 统一命名、程序集名称、根命名空间和入口方式

#### 需要改哪些文件

- `<ActorProjectPath>/<ActorProjectName>.csproj`
- `<ActorProjectPath>/Program.cs`
- `<ActorProjectPath>/GlobalUsings.cs`
- Actor 相关实现文件
- Actor / Worker 中的日志调用点

#### 参考文件来自哪里

- 同类已改造 Actor 宿主工程
- 当前组织内的 Dapr Actor 适配基础设施
- 已改造服务的 ASP.NET Core 入口模式

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                                       | 参考来源                             | 占位符参数                                                |
| ---------------------------------------------- | ------------------------------------ | --------------------------------------------------------- |
| `<ActorProjectPath>/<ActorProjectName>.csproj` | 同类已改造 Actor 宿主工程            | `<ActorProjectPath>` `<ActorProjectName>` `<ServiceName>` |
| `<ActorProjectPath>/Program.cs`                | 已改造服务的 ASP.NET Core 入口模式   | `<ActorProjectPath>` `<ActorProjectName>`                 |
| Actor 基类、扩展、注册逻辑                     | 当前组织内的 Dapr Actor 适配基础设施 | `<ServiceName>`                                           |
| `<ActorProjectPath>/GlobalUsings.cs`           | 已改造工程的 `GlobalUsings.cs`       | `<ActorProjectPath>`                                      |
| Actor / Worker 中的日志调用点                  | 基于 `AzureComputationContext.Logger` 的日志写法 | `<ActorProjectPath>` `<WorkerProjectPath>`                |

#### 内嵌示例

`Program.cs` 统一采用以下入口模式：

```csharp
using Slb.Prism.Rhapsody.Library.ComputationDaprAdapter.Extensions;

var builder = WebApplication.CreateBuilder(args);
var app = builder.BuildApplication<YourActor>();
app.Run();
```

如果原实现中使用了 `ServiceEventSource.Current.Information(...)` 或 `ServiceEventSource.Current.Error(...)`，迁移时需要统一替换为 `AzureComputationContext.Logger`。

示例：

```csharp
AzureComputationContext.Logger.Information("Start processing request {RequestId}", requestId);

try
{
    // business logic
}
catch (Exception ex)
{
    AzureComputationContext.Logger.Error(ex, "Processing failed for {RequestId}", requestId);
    throw;
}
```

#### 检查条件

- 宿主项目 SDK 为 `Microsoft.NET.Sdk.Web`
- `GenerateAssemblyInfo` 为 `false`
- `SharedAssemblyInfo.cs` 通过链接方式引入
- `Program.cs` 使用 Dapr Actor 启动模式
- 命名已从 `Computation` 切换到 `Service`
- 原有 `ServiceEventSource.Current.Information` / `ServiceEventSource.Current.Error` 已迁移到 `AzureComputationContext.Logger`

#### 验证逻辑

- 检查项目文件中的 SDK、包引用与链接项
- 检查 `Program.cs` 是否使用 Dapr Actor 宿主入口
- 搜索 `ServiceEventSource.Current.Information` 与 `ServiceEventSource.Current.Error`，确认已清理或替换
- 执行 `dotnet build`，确认 Actor 宿主编译通过

#### 单独签入要求

- Actor 宿主完成编译验证后，应立即单独提交一次，再进入下一阶段

### 4.5 可选 Worker 迁移

#### 要做什么

- 若旧工程存在 Stateless Worker，则将其迁移为 ASP.NET Core 后台服务
- 补齐独立部署与 Helm 子 chart 支撑

#### 需要改哪些文件

- `<WorkerProjectPath>/<WorkerProjectName>.csproj`
- `<WorkerProjectPath>/Program.cs`
- `<WorkerProjectPath>/appsettings.json`
- `deploy/charts/worker/**`

#### 参考文件来自哪里

- 同类已改造 Worker 服务
- 已改造服务中的 Worker 子 chart 结构

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                                         | 参考来源                            | 占位符参数                                  |
| ------------------------------------------------ | ----------------------------------- | ------------------------------------------- |
| `<WorkerProjectPath>/<WorkerProjectName>.csproj` | 同类已改造 Worker 工程文件          | `<WorkerProjectPath>` `<WorkerProjectName>` |
| `<WorkerProjectPath>/Program.cs`                 | 同类已改造 Worker 入口              | `<WorkerProjectPath>`                       |
| `deploy/charts/worker/**`                        | 已改造服务中的 Worker 子 chart 结构 | `<WorkerProjectName>` `<ServiceName>`       |

#### 检查条件

- Worker 已迁移为 ASP.NET Core 后台服务
- Worker 与 Actor 的部署边界清晰
- 若需独立部署，已存在 Worker 子 chart

#### 验证逻辑

- 执行 Worker 项目 `dotnet build`
- 执行 `helm template` 验证 Worker chart 可渲染

#### 单独签入要求

- Worker 独立迁移完成后，应立即单独提交一次，再进入下一阶段
- 若无 Worker，则跳过本阶段，不提交

### 4.6 配置与日志参数化

#### 要做什么

- 将配置迁移到新的宿主模型
- 为 Actor 与 Worker 补齐 `appsettings.json`
- 写入标准 logging 配置与 `ProviderName`

#### 需要改哪些文件

- `<ActorProjectPath>/appsettings.json`
- `<WorkerProjectPath>/appsettings.json`
- 可选环境配置文件

#### 参考文件来自哪里

- 同类已改造服务的 `appsettings.json`
- 当前 repo 旧配置文件

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                               | 参考来源                          | 占位符参数       |
| -------------------------------------- | --------------------------------- | ---------------- |
| `<ActorProjectPath>/appsettings.json`  | 同类已改造服务的标准 logging 配置 | `<ProviderName>` |
| `<WorkerProjectPath>/appsettings.json` | 同类已改造 Worker 配置            | `<ProviderName>` |

#### 内嵌示例

`appsettings.json` 至少包含以下结构：

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

#### 检查条件

- `Logging` 节点存在
- `LoggerSetup.EnricherConfiguration.Properties.ProviderName` 已写入 `<ProviderName>`
- 旧业务配置已迁移且语义未丢失

#### 验证逻辑

- 检查 JSON 结构完整
- 启动服务时确认配置可正常加载

#### 单独签入要求

- 配置迁移与日志参数化完成后，应立即单独提交一次，再进入下一阶段

### 4.7 版本与打包同步

#### 要做什么

- 根据 `ProviderName` 提取 `MajorVersion`
- 同步版本到 `SharedAssemblyInfo.cs`、主 `.nuspec`、`IntegrationTests` `.nuspec`
- 保留 NuGet 打包能力

#### 需要改哪些文件

- `SharedAssemblyInfo.cs`
- `<MainNuspecPath>`
- `<IntegrationTestsNuspecPath>`
- 可选 Contract `.nuspec`

#### 参考文件来自哪里

- 同类已改造服务的版本文件
- 当前 repo 现有 nuspec

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                       | 参考来源                        | 占位符参数                                     |
| ------------------------------ | ------------------------------- | ---------------------------------------------- |
| `SharedAssemblyInfo.cs`        | 同类已改造服务的版本文件        | `<MajorVersion>`                               |
| `<MainNuspecPath>`             | 同类已改造服务的主包 nuspec     | `<MainPackageId>` `<MajorVersion>`             |
| `<IntegrationTestsNuspecPath>` | 同类已改造服务的集成测试 nuspec | `<IntegrationTestsPackageId>` `<MajorVersion>` |

#### 内嵌示例

`SharedAssemblyInfo.cs` 的版本段建议如下：

```csharp
[assembly: AssemblyVersion("<MajorVersion>.0")]
[assembly: AssemblyFileVersion("<MajorVersion>.0.0.0")]
[assembly: AssemblyInformationalVersion("<MajorVersion>.0.0.0")]
```

主包 `.nuspec` 至少应包含以下文件项：

```xml
<files>
  <file src="deploy/**/*.*" target="" />
  <file src="SharedAssemblyInfo.cs" target="" />
  <file src="CustomizeValues.ps1" target="" />
</files>
```

#### 检查条件

- 三处版本保持一致
- 主包包含 `deploy/**/*.*`
- 主包包含 `SharedAssemblyInfo.cs`
- 主包包含 `CustomizeValues.ps1`
- 集成测试包包含测试输出目录

#### 验证逻辑

- 执行 `nuget.exe pack <MainNuspecPath>`
- 执行 `nuget.exe pack <IntegrationTestsNuspecPath>`
- 解包验证名称、版本、目录结构

#### 单独签入要求

- 版本与 nuspec 打包验证通过后，应立即单独提交一次，再进入下一阶段

### 4.8 Docker、本地调试与 Helm 产物补齐

#### 要做什么

- 补齐正式构建 `Dockerfile`
- 补齐本地验证 `DockerfileLocal`
- 补齐 `dapr.yaml`
- 补齐 `deploy/` Helm Chart

#### 需要改哪些文件

- `Dockerfile`
- `DockerfileLocal`
- `dapr.yaml`
- `deploy/**`
- `CustomizeValues.ps1`

#### 参考文件来自哪里

- 同类已改造服务的 Docker、Dapr 与 Helm 产物
- 当前 repo 旧部署产物与配置

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件              | 参考来源                         | 占位符参数                                |
| --------------------- | -------------------------------- | ----------------------------------------- |
| `Dockerfile`          | 同类已改造服务的正式镜像文件     | `<ActorProjectPath>` `<ActorProjectName>` |
| `DockerfileLocal`     | 同类已改造服务的本地镜像文件     | `<ActorProjectName>`                      |
| `dapr.yaml`           | 同类已改造服务的本地调试文件     | `<ActorProjectPath>` `<ServiceName>`      |
| `deploy/**`           | 同类已改造服务的 Helm Chart 结构 | `<ServiceName>` `<WorkerProjectName>`     |
| `CustomizeValues.ps1` | 已改造服务中的打包脚本           | `<ServiceName>`                           |

#### 内嵌示例

`dapr.yaml` 至少应覆盖以下形态：

```yaml
version: 1
apps:
  - appID: <ServiceName>
    appDirPath: <RepoPath>
    appPort: 5000
    daprHTTPPort: 3510
    command:
      - dotnet
      - run
      - --project
      - <ActorProjectPath>
    env:
      ASPNETCORE_ENVIRONMENT: Local
      DOTNET_ENVIRONMENT: Local
```

`CustomizeValues.ps1` 即使暂无逻辑，也必须保留：

```powershell
param()
```

#### 检查条件

- `Dockerfile` 用于 CI/CD 镜像构建
- `DockerfileLocal` 可本地 `docker build`
- `dapr.yaml` 可用于本地调试
- `deploy/` 可通过 `helm template` 渲染
- `CustomizeValues.ps1` 已打包

#### 验证逻辑

- 执行 `docker build -f .\\DockerfileLocal -t local-test .`
- 必要时执行 `dotnet publish` 后再用发布产物目录构建本地镜像
- 执行 `helm template local-test .\\deploy -f .\\deploy\\values.yaml`

#### 单独签入要求

- 容器、Dapr、本地部署产物验证通过后，应立即单独提交一次，再进入下一阶段

### 4.9 CI/CD 切换

#### 要做什么

- 将流水线切换到镜像构建与 Helm 部署链路
- 保证 `pipeline.json` 与 `azure-pipelines-ci.yml` 一致
- 明确本次任务对应的 `PipelineName`
- 若任务要求“提升发布 Pipeline”或“验证发布链路”，则同步核对该 `PipelineName` 对应的发布/部署 Pipeline 是否已切换到新产物与 Helm 部署链路

#### 需要改哪些文件

- `pipeline.json`
- `azure-pipelines-ci.yml`
- 可选 Azure DevOps 中与 `<PipelineName>` 对应的 Pipeline 配置记录

#### 参考文件来自哪里

- 同类已改造服务的流水线文件
- 当前组织内的流水线模板规范

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                 | 参考来源                             | 占位符参数                                                           |
| ------------------------ | ------------------------------------ | -------------------------------------------------------------------- |
| `pipeline.json`          | 同类已改造服务的流水线配置           | `<RepositoryName>` `<MainNuspecPath>` `<IntegrationTestsNuspecPath>` `<PipelineName>` |
| `azure-pipelines-ci.yml` | 同类已改造服务的 Azure Pipeline 入口 | `<RepositoryName>` `<PipelineName>`                                  |
| 发布/部署 Pipeline 记录  | Azure DevOps 中现有 Pipeline 定义    | `<PipelineName>`                                                     |

#### 内嵌示例

`pipeline.json` 至少应包含以下关键字段：

```json
{
  "type": "InternalImageDotNetCloud",
  "name": "<RepositoryName>",
  "workingBranch": "dapr",
  "buildAgent.template": "VS2022",
  "compile.platform": "x64",
  "pkg.nuspecPath": "<MainNuspecPath>",
  "pkg.nuspecIntPath": "<IntegrationTestsNuspecPath>",
  "pipelineTemplateVersion": "v3"
}
```

`azure-pipelines-ci.yml` 顶层模板至少应切换到：

```yaml
extends:
  template: tpl-InternalImageDotNetCloud.yml@rcis-devops-template
```

`azure-pipelines-ci.yml` 的parameters简化为

```yaml
parameters:
  - name: CDPkgVersion
    displayName: CD Package Version
    type: string
    default: stable
    values:
      - stable
      - latest
```

如需在文档或任务记录中引用目标流水线，统一使用：

```text
PipelineName = <PipelineName>
```

#### 检查条件

- `pipeline.json.type` 为镜像流水线类型
- `workingBranch` 存在且为 `dapr`
- `compile.platform` 为目标值
- `azure-pipelines-ci.yml` 使用 `tpl-InternalImageDotNetCloud.yml`
- 已确认本次任务对应的 `PipelineName`
- 打包路径、测试路径、Docker 文件路径正确
- 若任务要求提升发布 Pipeline，则 `<PipelineName>` 对应的发布链路已改为消费新 NuGet 包中的 `deploy/` 与 Helm Chart

#### 验证逻辑

- 人工核对 `pipeline.json` 关键字段
- 检查 `azure-pipelines-ci.yml` 顶层模板引用
- 记录并核对 `PipelineName`，确认它与本仓库和目标服务一一对应
- 确认部署阶段消费的是 NuGet 包内 `deploy/`
- 若任务要求提升发布 Pipeline，则核对 Azure DevOps 中 `<PipelineName>` 的发布定义、触发关系、工件来源、部署模板和目标环境配置

#### 单独签入要求

- 流水线文件自洽检查完成后，应立即单独提交一次，再进入下一阶段
- 若任务范围包含发布 Pipeline 提升，则在发布链路核对完成后，也应单独提交一次说明或脚本变更

### 4.10 清理 Service Fabric 资产

#### 要做什么

- 删除不再需要的 Service Fabric 资产、脚本、配置与依赖

#### 需要改哪些文件

- `*.sfproj`
- `ApplicationManifest.xml`
- `ServiceManifest.xml`
- `ApplicationPackageRoot/**`
- `PublishProfiles/**`
- Service Fabric 专属脚本、配置和依赖引用

#### 参考文件来自哪里

- 旧工程现状

#### 目标文件 + 参考文件 + 占位符参数

| 目标文件                                              | 参考文件   | 占位符参数                                 |
| ----------------------------------------------------- | ---------- | ------------------------------------------ |
| `*.sfproj` / Manifest / PackageRoot / PublishProfiles | 旧工程现状 | `<RepoPath>`                               |
| `*.csproj` 中的 Service Fabric 包引用                 | 旧工程现状 | `<ActorProjectPath>` `<WorkerProjectPath>` |

#### 检查条件

- repo 中不再残留 Service Fabric 专属资产
- 项目文件中不再引用失效依赖
- 旧部署模型文件已从解决方案和打包链路移除

#### 验证逻辑

- 搜索 `*.sfproj`
- 搜索 `ApplicationManifest.xml`、`ServiceManifest.xml`
- 搜索 `ApplicationPackageRoot`、`PublishProfiles`
- 搜索 Service Fabric 相关包名与命名空间

#### 单独签入要求

- 清理完成并通过搜索校验后，应立即单独提交一次，再进入最终验收

### 4.11 最终统一验收

#### 要做什么

- 对升级结果做统一核对，确保前面所有阶段的产物闭环
- 在最终验收前统一执行 CRLF 归一化脚本，保证本地文本文件换行为 Windows `CR/LF`

#### 需要改哪些文件

- 本步骤原则上不修改文件，仅验证
- 若存在 `LF`-only 文本文件，则通过 `scripts/normalize-crlf.ps1` 修正为 `CR/LF`

#### 参考文件来自哪里

- 当前 repo 最终状态
- `../Rhapsody.Service.DrillingKpi`

#### 检查条件

- 命名已全部切换到 `Slb.Prism.Rhapsody.Service.*`
- 版本在 `SharedAssemblyInfo.cs`、主 `.nuspec`、`IntegrationTests` `.nuspec` 中一致
- `pipeline.json` 与 `azure-pipelines-ci.yml` 共同切换到镜像流水线
- `PipelineName` 已确认且记录在任务输出中
- `deploy/`、`CustomizeValues.ps1`、`DockerfileLocal`、`dapr.yaml` 齐全
- repo 内目标文本文件换行统一为 `CR/LF`
- 已经是 `CR/LF` 的文件不会被重复写回，避免产生无意义 file change
- `dotnet build`、`dotnet test`、`nuget pack`、`helm template` 通过
- 若任务要求提升发布 Pipeline，则发布链路也已完成核对或执行验证
- 若 `UnitTests`、`IntegrationTests`、主工程编译、打包、渲染、Pipeline 任一项未通过、未执行或仅部分完成，必须在最终结果中逐项报告，不允许省略

#### 验证逻辑

- 执行 `powershell -ExecutionPolicy Bypass -File .\scripts\normalize-crlf.ps1 -RootPath .`
- 脚本输出若为 `All matching text files already use CRLF. No files were changed.`，表示无额外文件变更
- 按第 8 章验收命令清单统一执行
- 对照第 6 章最终统一核对项逐项确认
- 记录 `PipelineName` 以及发布链路验证结果
- 记录 `UnitTests`、`IntegrationTests`、`dotnet build`、`nuget pack`、`helm template`、`pipeline` 的实际执行结果；若有失败、跳过或阻塞，需写明原因

#### 单独签入要求

- 最终验收前先执行 `powershell -ExecutionPolicy Bypass -File .\scripts\normalize-crlf.ps1 -RootPath .`
- 只有在 CRLF 归一化完成后，才允许进行本阶段相关提交
- 如果脚本输出 `All matching text files already use CRLF. No files were changed.`，可直接继续提交
- 如果脚本修正了 `LF`-only 文件，应先确认这些变更仅为换行修正，再与本阶段改动一并提交
- 如最终验收阶段未引入修复，则不提交
- 如为通过最终验收而产生修复，修复内容按问题类型单独提交
- 若任务目标是“升级并验证”，且所有仓库内改动已完成并通过当前环境可执行验证，则默认需要完成至少一次最终签入；只有在外部依赖、凭据、权限或用户明确要求不提交时，才允许不签入，但必须在结果中明确阻塞原因

## 5. 每步验证与单独签入要求

执行具体升级任务时，应按以下阶段粒度进行多次签入，而不是把所有改动堆积到最后统一签入：

| 阶段                          | 是否应单独提交 | 说明                   |
| ----------------------------- | -------------- | ---------------------- |
| 创建 `dapr` 分支              | 否             | 分支动作，不提交       |
| 基线盘点与迁移清单            | 可选           | 仅在产生盘点文档时提交 |
| 解决方案与项目结构调整        | 是             | 保持结构类变更独立     |
| Actor 宿主迁移                | 是             | 核心运行时变更独立     |
| Worker 迁移                   | 是             | 可选阶段，但若执行则应独立 |
| 配置与日志参数化              | 是             | 避免与代码迁移混杂     |
| 版本与打包同步                | 是             | 便于回溯版本链路       |
| Docker / Dapr / Helm 产物补齐 | 是             | 交付物变更独立         |
| CI/CD 切换                    | 是             | 便于单独审核           |
| 发布 Pipeline 提升            | 是             | 便于区分仓库内改动与平台侧变更 |
| 清理 Service Fabric 资产      | 是             | 删除类改动独立         |
| 最终统一验收修复              | 视情况         | 仅在出现验收问题时提交 |

每次提交前至少满足以下要求：

- 当前阶段定义的检查条件已满足
- 当前阶段定义的验证命令已执行
- 当前阶段改动不依赖后续阶段才能通过基本检查
- 若提交前涉及文本文件，先执行 `scripts/normalize-crlf.ps1`，确保本地文本文件为 `CR/LF`
- 已经是 `CR/LF` 的文件不应被重复写回，避免引入无意义 file change
- 若进入下一个阶段前，当前阶段已经形成稳定结果，则应先完成该阶段签入，再继续后续改造
- 不允许用最后一次总签入替代前面应有的阶段签入，除非用户在任务开始时明确要求不要拆分提交，或被外部阻塞无法提前形成可提交状态
- 若任务目标已明确要求“升级并验证”，则在仓库内改动完成后，不应停留在未签入状态；除阶段性签入外，还应在最终收尾时确认没有遗留未签入改动，除非被外部阻塞

## 6. 最终统一核对

最终统一核对时，至少检查以下事项：

### 6.1 命名核对

- 服务命名已从 `Slb.Prism.Rhapsody.Computation.*` 切换到 `Slb.Prism.Rhapsody.Service.*`
- 程序集名称、命名空间、包名、镜像名、Helm release 相关值保持一致

### 6.2 版本核对

- `SharedAssemblyInfo.cs`
- `<MainNuspecPath>`
- `<IntegrationTestsNuspecPath>`

以上文件中的版本必须一致，且主版本来自 `ProviderName` 尾号。

### 6.3 交付物核对

- 存在 `Dockerfile`
- 存在 `DockerfileLocal`
- 存在 `dapr.yaml`
- 存在 `deploy/`
- 存在 `CustomizeValues.ps1`
- 存在 `scripts/normalize-crlf.ps1`
- 主 `.nuspec` 中已包含 `deploy/**/*.*`
- 集成测试包可打包并包含测试输出

### 6.4 流水线核对

- `pipeline.json` 已切换到镜像流水线类型
- `pipeline.json` 包含 `workingBranch`
- `compile.platform` 已切换到目标值
- `azure-pipelines-ci.yml` 引用 `tpl-InternalImageDotNetCloud.yml`
- `PipelineName` 已明确且与目标服务对应
- 流水线消费的打包、镜像、部署路径与 repo 现状一致
- 若任务范围包含发布 Pipeline，则对应发布 Pipeline 已切换到新的工件与 Helm 部署链路

### 6.5 运行与渲染核对

- `dotnet restore` 通过
- `dotnet build -c Release` 通过
- `dotnet test -c Release` 通过
- `nuget.exe pack` 通过
- `powershell -ExecutionPolicy Bypass -File .\scripts\normalize-crlf.ps1 -RootPath .` 已执行
- `docker build -f .\\DockerfileLocal -t local-test .` 通过
- `helm template local-test .\\deploy -f .\\deploy\\values.yaml` 通过
- 若上述任一项未通过、未执行或仅完成部分工程，必须在最终结果中明确列出“已通过 / 未通过 / 未执行 / 被阻塞”状态，尤其要单独标明 `UnitTests` 与 `IntegrationTests`

## 7. 常见失配检查

后续 task 中，优先检查以下高频失配问题：

- `SharedAssemblyInfo.cs` 与 `.nuspec` 版本不一致
- `pipeline.json` 缺少 `workingBranch`
- 未确认 `PipelineName`，导致修改了错误的 Pipeline
- `compile.platform` 仍是旧值，不满足目标要求
- `azure-pipelines-ci.yml` 仍引用旧的 Service Fabric 模板
- Docker 文件命名与 `pipeline.json` / 实际构建入口不一致
- `CustomizeValues.ps1` 缺失，导致部署阶段可能回退到底层默认 `deployTemplate`
- 主包未包含独立 `deploy/` 目录
- 仅修改了 `pipeline.json.type`，但未同步更新 `azure-pipelines-ci.yml`
- 仅修改了 CI Pipeline 文件，但未同步核对或提升发布 Pipeline
- 服务命名、程序集命名、包命名仍混用 `Computation` 与 `Service`

## 8. 参考来源映射表

参考来源按用途归类如下：

| 用途                    | 参考来源                             | 使用原则                         |
| ----------------------- | ------------------------------------ | -------------------------------- |
| Actor / Web 宿主参考    | 任一同类已改造 Actor 服务            | 仅借鉴结构与模式，不依赖固定路径 |
| Dapr Actor 基础设施参考 | 当前组织内的 Dapr Actor 适配基础设施 | 优先复用已有扩展与基类           |
| Worker 参考             | 任一同类已改造 Worker 服务           | 仅借鉴后台服务与部署结构         |
| Helm / 打包 / 管线参考  | 当前组织内统一模板与已改造服务       | 以规范字段和结构为准             |
| 配置与反例补充参考      | 当前 repo 历史实现与已改造样例       | 用于识别迁移遗漏与失配           |

说明：

- 不要把某个固定外部目录写成升级前置条件
- 短小且稳定的配置、入口、版本、流水线片段，应优先以内嵌示例方式写入本文档
- 只有当实现体量较大、且无法通过短示例表达时，才使用“按用途寻找同类样例”的描述

## 9. 验收命令清单

建议按以下顺序执行最终验收：

### 9.1 编译

```powershell
dotnet restore
dotnet build -c Release
```

### 9.1A CRLF 归一化

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\normalize-crlf.ps1 -RootPath .
```

要求：

- 目标文本文件最终全部为 `CR/LF`
- 已经是 `CR/LF` 的文件不应被写回
- 若脚本输出 `All matching text files already use CRLF. No files were changed.`，说明没有无意义变更

### 9.2 测试

```powershell
dotnet test -c Release
```

### 9.3 版本一致性检查

- 检查 `SharedAssemblyInfo.cs`
- 检查 `<MainNuspecPath>`
- 检查 `<IntegrationTestsNuspecPath>`

### 9.4 NuGet 打包与解包验证

```powershell
nuget.exe pack <MainNuspecPath>
nuget.exe pack <IntegrationTestsNuspecPath>
```

重点检查：

- 包名正确
- 版本正确
- 主包包含 `SharedAssemblyInfo.cs`
- 主包包含独立 `deploy/`
- 主包包含 `CustomizeValues.ps1`
- 集成测试包包含测试输出目录

### 9.5 Dapr 本地调试检查

- repo 根目录存在 `dapr.yaml`
- 本地组件目录可用
- Actor 项目路径正确
- 环境变量完整

### 9.6 Docker 本地打包验证

```powershell
docker build -f .\DockerfileLocal -t local-test .
```

使用发布产物目录作为构建上下文：

```powershell
dotnet publish .\YourActorProject\YourActorProject.csproj -c Release -o .\artifacts\publish\actor
docker build -f ..\..\DockerfileLocal -t local-test --build-arg APP_DLL=YourServiceActor.dll .\artifacts\publish\actor
```

### 9.7 Helm 渲染验证

```powershell
helm template local-test .\deploy -f .\deploy\values.yaml
```

如存在本地 values 文件，可继续执行：

```powershell
helm template local-test .\deploy -f .\deploy\values.yaml -f .\deploy\values.local.k8s.yaml
```

### 9.8 Pipeline 名称与发布链路验证

- 确认任务输入中存在 `PipelineName`
- 确认 `PipelineName` 与当前 repo、服务名、默认分支和部署目标一致
- 若任务要求提升发布 Pipeline，检查该 `PipelineName` 对应发布链路是否满足以下条件：
  - 消费升级后的主包或镜像产物
  - 部署入口改为 Helm Chart，而不是 Service Fabric Application 包
  - 目标环境变量、参数名和制品路径与仓库现状一致

建议记录：

```text
PipelineName: <PipelineName>
PublishPipelineValidated: Yes/No
PublishPipelineExecuted: Yes/No
```

### 9.9 最终签入验证

```powershell
git status --short
git log -1 --oneline
```

要求：

- 对于“升级并验证”类任务，最终不应停留在未签入状态
- 应能从提交历史看出关键阶段的多次签入，不应只有一次末尾总签入
- 若阶段性签入要求被跳过，必须在结果中说明跳过原因
- 若因外部依赖、凭据、权限或用户决策未能签入，必须在任务结果中明确说明原因

### 9.10 Pipeline 执行前准备

执行 Azure DevOps Pipeline 前，至少满足以下本地前置条件：

- 已安装 Azure CLI
- 已安装 Azure DevOps Azure CLI 扩展 `azure-devops`
- 当前终端已完成 Azure 登录
- 当前终端已完成 Azure DevOps scope 登录
- 已确认 `<PipelineName>`
- 目标分支已推送到远端

建议先执行以下检查：

```powershell
az --version
az extension list -o table
az account show
git branch --show-current
git push -u origin <BranchName>
```

如未安装 Azure DevOps 扩展，执行：

```powershell
az extension add -n azure-devops -y
```

如未完成 Azure 登录，执行：

```powershell
az login
```

如未完成 Azure DevOps scope 登录，执行：

```powershell
az login --scope 499b84ac-1321-427f-aa17-267ca6975798/.default
```

如需固定默认组织和项目，可执行：

```powershell
az devops configure --defaults organization=https://dev.azure.com/slb1-swt project=Prism
```

### 9.11 最终执行 Pipeline 脚本

推荐在最终签入并 `push` 完成后，再执行 Pipeline。默认参数为 `CDPkgVersion=latest`。

如已知 `<PipelineId>`，可直接执行：

```powershell
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}
$body = @{
    resources = @{
        repositories = @{
            self = @{
                refName = "refs/heads/<BranchName>"
            }
        }
    }
    templateParameters = @{
        CDPkgVersion = "latest"
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
    -Uri "https://dev.azure.com/slb1-swt/Prism/_apis/pipelines/<PipelineId>/runs?api-version=7.1-preview.1" `
    -Headers $headers `
    -Method Post `
    -Body $body
```

如尚未确认 `<PipelineId>`，建议先按 `<PipelineName>` 查询：

```powershell
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }
$uri = "https://dev.azure.com/slb1-swt/Prism/_apis/pipelines?api-version=7.1-preview.1"

(Invoke-RestMethod -Uri $uri -Headers $headers -Method Get).value |
    Where-Object { $_.name -eq "<PipelineName>" } |
    Select-Object id, name, folder
```

执行后，建议立即查询运行状态：

```powershell
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

Invoke-RestMethod `
    -Uri "https://dev.azure.com/slb1-swt/Prism/_apis/build/builds/<RunId>?api-version=7.1-preview.7" `
    -Headers $headers `
    -Method Get |
    Select-Object id, buildNumber, status, result, sourceBranch, queueTime, startTime
```

要求：

- Pipeline 执行时应明确记录 `<PipelineName>`、`<PipelineId>`、`<RunId>`、`<BranchName>`
- 默认执行参数为 `CDPkgVersion=latest`
- 若脚本执行失败，应记录失败命令、错误信息和当前阻塞点

## 10. 输出要求

后续每个具体升级 task 在引用本文档时，至少应显式给出以下信息：

- `RepoPath`
- `ProviderName`
- `PipelineName`
- 是否包含 Worker
- 是否需要保留 Contract 工程
- 主包与 `IntegrationTests` 包名称

最终交付物应满足：

- 工程已完成从 Service Fabric Actor 到 Dapr Actor 的迁移
- 版本与打包信息一致
- 本地调试、容器构建、Helm 渲染、测试执行均可验证
- 已明确目标 `PipelineName`
- 若任务要求提升发布 Pipeline，则已完成对应验证或执行结果说明
- 每个阶段均有对应检查条件、验证逻辑与建议提交粒度
- 最终结果必须包含验证摘要，至少列出以下项目的状态：`UnitTests`、`IntegrationTests`、主工程 `dotnet build`、`nuget pack`、`helm template`、`docker build`、`pipeline`
- 对于任何失败、未执行或被阻塞的项，必须明确给出原因、影响范围和下一步动作

## 11. 交付后的 Pipeline 处理

完成代码改造与本地验证后，按以下规则处理 pipeline：

- 如果用户在任务一开始已经明确要求执行 pipeline，则按用户要求执行
- 如果用户一开始没有要求执行 pipeline，则不要默认直接执行，而是先询问用户是否需要执行
- 当需要执行 pipeline 时，默认使用参数 `CDPkgVersion=latest`
- 如果任务要求“提升发布 Pipeline”，则不能只修改仓库内 `pipeline.json` 和 `azure-pipelines-ci.yml`，还必须显式核对或执行 `<PipelineName>` 对应的发布链路
- 如果任务要求“升级并验证”，则除非存在外部阻塞，否则应在仓库内按阶段完成多次签入，并在最终收尾时确认没有剩余未签入改动
- 如果未能签入或未能提升发布 Pipeline，必须在最终结果中给出明确原因、当前阻塞点和下一步动作
- 如果 `UnitTests`、`IntegrationTests` 或其他关键验证未跑通，必须在最终结果中单独报告；不能用“已验证”或“基本完成”之类表述覆盖掉失败项

建议询问方式：

- 是否需要我继续帮你触发 pipeline 验证？如果执行，默认使用 `CDPkgVersion=latest`。
