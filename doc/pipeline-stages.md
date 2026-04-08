# Rhapsody.Service.RtRheology Pipeline Stages 文档

## 1. 文档目的

本文基于以下三类资料，整理 `Rhapsody.Computation.RtRheology` 的 Azure CI/CD
Pipeline 在 stage 级别上的输入、依赖和产出：

- 仓库入口文件 `Rhapsody.Computation.RtRheology/azure-pipelines-ci.yml`
- 模板仓库 `../Pipeline/rcis-devops-template`
- 成功运行样本 `Rhapsody.Computation.RtRheology_15507955`

本文的目标是回答三个问题：

1. 每个 stage 依赖仓库中的哪些非代码文件
2. 每个 stage 依赖哪些上游 stage 的输出
3. 每个 stage 会产出什么结果，供后续 stage 或外部系统使用

## 2. Pipeline 类型与入口

### 2.1 仓库入口

- Pipeline 入口文件：`azure-pipelines-ci.yml`
- 使用模板：`tpl-InternalImageDotNetCloud.yml@rcis-devops-template`
- 模板类型：`InternalImageDotNetCloud`

### 2.2 实际 stage 链路

展开后的 Pipeline 包含以下 stage，名称必须与 YAML 保持一致：

1. `CodeChange`
2. `PKG`
3. `QC`
4. `Image`
5. `Deploy`
6. `IT`
7. `FIT`
8. `Publish`

### 2.3 Stage 依赖关系

```text
CodeChange
  -> PKG
  -> QC
  -> Image
  -> Deploy
  -> IT
  -> FIT
  -> Publish

PKG
  -> QC
  -> Image
  -> Deploy
  -> IT
  -> FIT
  -> Publish

QC
  -> Image

Image
  -> Deploy

Deploy
  -> IT

IT
  -> FIT

FIT
  -> Publish
```

## 3. 与 Stage 相关的仓库输入

下列文件会被多个 stage 直接或间接使用，因此先统一列出：

| 路径                                                                             | 作用                                                   |
| -------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `azure-pipelines-ci.yml`                                                         | Pipeline 入口，定义模板、触发条件和参数                |
| `pipeline.json`                                                                  | CD 类型、nuspec 路径、测试开关、代码扫描目录等核心配置 |
| `Slb.Prism.Rhapsody.Service.RtRheology.nuspec`                                   | 主服务 NuGet 包定义                                    |
| `IntegrationTests/Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.nuspec` | 集成测试 NuGet 包定义                                  |
| `Dockerfile`                                                                     | 镜像构建输入                                           |
| `DockerfileLocal`                                                                | 本地镜像调试文件，不是本次 CI 主路径                   |
| `deploy/Chart.yaml`                                                              | Helm Chart 元数据                                      |
| `deploy/values.yaml`                                                             | Helm 默认 values                                       |
| `deploy/templates/*.yaml`                                                        | Helm 模板                                              |
| `CustomizeValues.ps1`                                                            | Deploy 阶段自定义 values 扩展脚本                      |
| `SharedAssemblyInfo.cs`                                                          | 打包时进入 NuGet 包，也参与版本写入                    |
| `Rhapsody.Service.RtRheology.slnx`                                               | `ut`、`pkg` 编译输入                                   |

其中 `pipeline.json` 的关键信息如下：

- `type = InternalImageDotNetCloud`
- `pkg.nuspecPath = Slb.Prism.Rhapsody.Service.RtRheology.nuspec`
- `pkg.nuspecIntPath = IntegrationTests/Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.nuspec`
- `it.runs = NoAction`
- `fit.filter = TestCategory~RtRheology`
- `codescan.sourceDirs = ComputationActor`
- `pipelineTemplateVersion = v3`

## 4. Stage 级别说明

### 4.1 `CodeChange`

#### 4.1.1 作用

初始化本次流水线使用的 CD 包版本，并执行模板中的 `CodeChange` 检查逻辑。

#### 4.1.2 Job

- `codechange`

#### 4.1.3 直接依赖的仓库输入

- 仓库源码本身
- `azure-pipelines-ci.yml`

#### 4.1.4 直接依赖的外部输入

- Pipeline 参数 `CDPkgVersion`
- 模板仓库中的 `tpl-InternalImageDotNetCloud.yml`
- `Slb.Prism.CD.Pipeline` NuGet 包

#### 4.1.5 关键处理

- `Process Parameters` 步骤根据参数决定本次使用的 CD 包版本
- 运行样本 `15507955` 中，解析结果为 `CDPkgVersion = 2.192.0`
- 同时生成 `defaultPipelineConfig`
- 将 build number 临时更新为 `(Not Packaged)`

#### 4.1.6 传递给后续 stage 的输出

| 输出名                  | 来源                                      | 用途                                                    |
| ----------------------- | ----------------------------------------- | ------------------------------------------------------- |
| `CDPkgVersion`          | `ProcessParameters.CDPkgVersion`          | 后续 stage 下载并执行对应版本的 `Slb.Prism.CD.Pipeline` |
| `defaultPipelineConfig` | `ProcessParameters.defaultPipelineConfig` | 后续 stage 选择默认 CD 配置                             |

#### 4.1.7 产出

- Stage 输出变量：
  - `CDPkgVersion`
  - `defaultPipelineConfig`
- 构建摘要附件：
  - `summary-cdpkgselection.md`

### 4.2 `PKG`

#### 4.2.1 作用

完成单元测试、代码扫描和 NuGet 打包，并把打包结果上传为 Pipeline Artifact。

#### 4.2.2 Jobs

- `ut`
- `codescan`
- `pkg`

#### 4.2.3 Stage 依赖

- 依赖 `CodeChange`
- 使用 `CodeChange` 传出的：
  - `CDPkgVersion`
  - `defaultPipelineConfig`

#### 4.2.4 直接依赖的仓库输入

- `Rhapsody.Service.RtRheology.slnx`
- `pipeline.json`
- `Slb.Prism.Rhapsody.Service.RtRheology.nuspec`
- `IntegrationTests/Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.nuspec`
- `SharedAssemblyInfo.cs`
- `deploy/**`
- `CustomizeValues.ps1`

#### 4.2.5 `ut` Job

输入：

- 解决方案 `Rhapsody.Service.RtRheology.slnx`
- 单元测试项目与主项目源码

实际执行：

- `dotnet build ... -c Release`
- `vstest.console.exe ... UnitTests.dll /logger:trx /platform:x64 /EnableCodeCoverage`

实际产出：

- 编译输出：
  - `artifacts/bin/Slb.Prism.Rhapsody.Service.RtRheologyActor/release/...`
  - `artifacts/bin/UnitTests/release/...`
  - `artifacts/bin/IntegrationTests/release/...`
- 测试结果：
  - `**/ut/**/*.trx`
- 覆盖率附件：
  - `.coverage`

运行样本 `15507955` 中：

- 共执行 1 个单元测试
- 结果为 `Passed: 1`

#### 4.2.6 `codescan` Job

输入：

- `pipeline.json`
  - `codescan.sourceDirs = ComputationActor`
  - `codescan.excludeDirs = **/*Tests*/**`

实际产出：

- 代码扫描结果
- 供 `QC` 阶段读取的扫描指标输出

说明：

- 展开后的 YAML 中，`QC` 会读取 `gocodescan.MaxMethodComplexity`
- 样本运行中 `QC` 因 SonarQube 维护被跳过，因此没有看到后续展示内容

#### 4.2.7 `pkg` Job

输入：

- `Slb.Prism.Rhapsody.Service.RtRheology.nuspec`
- `IntegrationTests/Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.nuspec`
- `deploy/**`
- `CustomizeValues.ps1`
- `SharedAssemblyInfo.cs`

实际执行：

- 先编译解决方案
- 再执行两次 `nuget pack`
- 再执行两次 `nuget push`
- 最后把 `_w/pkg` 上传为 Pipeline Artifact `pkg`

样本运行 `15507955` 中实际生成的 NuGet 版本：

- `2.0.0-ci.15507955`

样本运行中实际发布的包：

- `Slb.Prism.Rhapsody.Service.RtRheology.2.0.0-ci.15507955.nupkg`
- `Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.2.0.0-ci.15507955.nupkg`

上传到 Pipeline Artifact `pkg` 时，日志显示：

- 源目录：`C:\azp\agent\_work\1\s\_w\pkg`
- 处理文件数：`2`

#### 4.2.8 传递给后续 stage 的输出

| 输出名             | 来源                      | 用途                                                                         |
| ------------------ | ------------------------- | ---------------------------------------------------------------------------- |
| `gopkg.PkgVersion` | `pkg` Job                 | 被 `Image`、`Deploy`、`IT`、`FIT`、`Publish` 作为 `NuGetPackageVersion` 使用 |
| `pkg` Artifact     | `PublishPipelineArtifact` | 被 `Deploy`、`IT` 下载                                                       |

#### 4.2.9 产出

- Pipeline Artifact：
  - `pkg`
- NuGet 包：
  - 主服务包
  - 集成测试包
- 测试结果：
  - UT `.trx`
- 构建摘要附件：
  - `summary-pkgversion.md`

### 4.3 `QC`

#### 4.3.1 作用

执行质量检查，并在需要时把代码度量信息附加到构建摘要中。

#### 4.3.2 Job

- `qc`

#### 4.3.3 Stage 依赖

- 依赖 `CodeChange`
- 依赖 `PKG`
- 读取上游输入：
  - `CDPkgVersion`
  - `defaultPipelineConfig`
  - `gocodescan.MaxMethodComplexity`

#### 4.3.4 直接依赖的仓库输入

- `pipeline.json`

#### 4.3.5 实际行为

样本运行 `15507955` 中：

- `go qc` 任务输出 `SKIP QC due to sonarqube maintenance`
- `Display Code Metrics` 步骤执行了，但没有附加实际指标内容

代码中的展示逻辑依赖：

- `pipeline.json`
- `pipeline.json` 中的 `qc.runs`
- `_w/summary-codemetrics.md`

#### 4.3.6 产出

正常情况下：

- 质量检查结果
- `summary-codemetrics.md`

样本运行 `15507955` 中：

- 无实际 code metrics 摘要内容
- Stage 成功结束

### 4.4 `Image`

#### 4.4.1 作用

用仓库中的 `Dockerfile` 构建镜像并推送到 ACR。

#### 4.4.2 Job

- `image`

#### 4.4.3 Stage 依赖

- 依赖 `CodeChange`
- 依赖 `PKG`
- 依赖 `QC`
- 读取上游输入：
  - `CDPkgVersion`
  - `defaultPipelineConfig`
  - `NuGetPackageVersion = gopkg.PkgVersion`

#### 4.4.4 直接依赖的仓库输入

- `Dockerfile`
- `Directory.Build.props`
- `ComputationActor/Slb.Prism.Rhapsody.Service.RtRheologyActor.csproj`
- `UnitTests/UnitTests.csproj`
- `IntegrationTests/IntegrationTests.csproj`
- 其余源码文件

#### 4.4.5 实际行为

样本运行 `15507955` 中：

- 使用 Linux agent
- 读取仓库根目录 `Dockerfile`
- 构建镜像名：
  - `drillops.azurecr.io/rhapsody/rtrheology:2.0.0-ci.15507955`
- 额外推送：
  - `drillops.azurecr.io/rhapsody/rtrheology:latest`

#### 4.4.6 产出

- ACR 镜像：
  - `drillops.azurecr.io/rhapsody/rtrheology:2.0.0-ci.15507955`
  - `drillops.azurecr.io/rhapsody/rtrheology:latest`
- 镜像摘要：
  - `sha256:02082d8a30c21b9dc63203b8b89f4759964f0c0c12cdc592309cc4825c34aba7`

说明：

- `Image` stage 不向后续 stage 发布 Pipeline Artifact
- `Deploy` 通过版本号和 Chart values 间接消费镜像结果

### 4.5 `Deploy`

#### 4.5.1 作用

下载 `PKG` 阶段产出的 NuGet 包，渲染 Helm Chart，并把服务部署到 AKS。

#### 4.5.2 Job

- `deploy`

#### 4.5.3 Stage 依赖

- 依赖 `CodeChange`
- 依赖 `PKG`
- 依赖 `Image`
- 读取上游输入：
  - `CDPkgVersion`
  - `defaultPipelineConfig`
  - `NuGetPackageVersion = gopkg.PkgVersion`
- 下载上游 Artifact：
  - `pkg`

#### 4.5.4 直接依赖的仓库输入

此阶段直接消费的是 `pkg` Artifact 中的包内容，因此仓库内对它有影响的文件是：

- `Slb.Prism.Rhapsody.Service.RtRheology.nuspec`
- `deploy/Chart.yaml`
- `deploy/values.yaml`
- `deploy/templates/*.yaml`
- `CustomizeValues.ps1`

#### 4.5.5 部署前处理

样本运行 `15507955` 中，`Deploy` 先安装：

- `Slb.Prism.Rhapsody.Service.RtRheology 2.0.0-ci.15507955`

随后在包目录下处理 Helm Chart：

- Chart 目录：
  `C:\azp\agent\_work\1\s\_w\_t\Slb.Prism.Rhapsody.Service.RtRheology.2.0.0-ci.15507955\deploy`
- 自动生成或覆盖：
  - `values-1-calculated.yaml`
  - `values-2-deployargs.yaml`
  - `values-3-customized.yaml`

日志中可见被更新的 key：

- `image`
- `environmentVariables`
- `replicaCount`
- `affinity`
- `strategy`
- `ingress.enabled`

#### 4.5.6 实际部署命令

样本运行中执行：

```text
helm upgrade --install rtrheology-2 <package>\deploy -n rhapsody
  --set envType=dev
  --set worker.envType=dev
  -f values-1-calculated.yaml
  -f values-2-deployargs.yaml
```

#### 4.5.7 样本运行中的最终部署结果

- 发布目标服务名：`slb.prism.rhapsody.service.rtrheology-2`
- Helm release：`rtrheology-2`
- Namespace：`rhapsody`
- Status：`deployed`
- Revision：`4`
- Pod 就绪结果：新 Pod `2/2 Running`

#### 4.5.8 产出

- AKS 中的新版本部署
- 渲染后的 values 文件：
  - `values-1-calculated.yaml`
  - `values-2-deployargs.yaml`
  - `values-3-customized.yaml`
- 网关注册相关后处理结果

### 4.6 `IT`

#### 4.6.1 作用

下载 `PKG` 阶段生成的集成测试 NuGet 包，并在目标环境执行 Integration Test。

#### 4.6.2 Job

- `it`

#### 4.6.3 Stage 依赖

- 依赖 `CodeChange`
- 依赖 `PKG`
- 依赖 `Deploy`
- 读取上游输入：
  - `CDPkgVersion`
  - `defaultPipelineConfig`
  - `NuGetPackageVersion = gopkg.PkgVersion`
- 下载上游 Artifact：
  - `pkg`

#### 4.6.4 直接依赖的仓库输入

影响此阶段的仓库文件主要是：

- `IntegrationTests/Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.nuspec`
- `pipeline.json`

#### 4.6.5 实际行为

样本运行 `15507955` 中：

- 安装包：
  `Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.2.0.0-ci.15507955`
- 在 `_w/it/.../bin/Release/net10.0/` 下执行：
  `vstest.console.exe ... Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.dll`

测试结果：

- 发现 1 个测试程序集
- 共 1 个测试
- `Passed: 1`

#### 4.6.6 产出

- IT 测试结果：
  - `**/it/**/*.trx`
- Integration Test 运行日志

### 4.7 `FIT`

#### 4.7.1 作用

执行 Full Integration Test 或 E2E Test 的占位流程。

#### 4.7.2 Job

- `fit`

#### 4.7.3 Stage 依赖

- 依赖 `CodeChange`
- 依赖 `PKG`
- 依赖 `IT`
- 读取上游输入：
  - `CDPkgVersion`
  - `defaultPipelineConfig`
  - `NuGetPackageVersion = gopkg.PkgVersion`

#### 4.7.4 直接依赖的仓库输入

- `pipeline.json`

#### 4.7.5 实际行为

样本运行 `15507955` 中：

- `go fit` 判断：
  `End2EndTest is skipped because no fit pkg is specified in pipeline.json`

这说明：

- Stage 会执行
- 但是否真的跑 E2E/FIT，取决于 `pipeline.json` 中是否给出可执行的 fit 包配置

#### 4.7.6 产出

正常情况下：

- FIT 测试结果：
  - `**/fit/**/*.trx`

样本运行 `15507955` 中：

- 无实际测试产物
- Stage 成功结束

### 4.8 `Publish`

#### 4.8.1 作用

把最终发布元数据写入发布目录，并上传到外部存储，作为后续系统可消费的发布记录。

#### 4.8.2 Job

- `publish`

#### 4.8.3 Stage 依赖

- 依赖 `CodeChange`
- 依赖 `PKG`
- 依赖 `FIT`
- 读取上游输入：
  - `CDPkgVersion`
  - `defaultPipelineConfig`
  - `NuGetPackageVersion = gopkg.PkgVersion`

#### 4.8.4 直接依赖的仓库输入

- `pipeline.json`

#### 4.8.5 实际行为

样本运行 `15507955` 中：

- 生成发布元数据文件：
  - `_w/publish/2.0.0-ci.15507955.json`
- 通过 `azcopy` 上传到 Blob Storage：
  - `https://devopspipelinesa.blob.core.windows.net/build/rhapsody/rhapsody.service.rtrheology/`

日志中的完整动作可以概括为：

- 生成 publish JSON
- 上传 JSON 到 Blob
- 如果配置了 fit 包，则继续处理 E2E 相关逻辑

本次运行中：

- `End2EndTest is skipped because no fit pkg is specified in pipeline.json`

#### 4.8.6 产出

- 发布元数据文件：
  - `2.0.0-ci.15507955.json`
- Blob Storage 中对应服务目录下的发布记录

## 5. Stage 与产物对照表

| Stage        | 读取的关键仓库文件                                                            | 读取的上游产物                               | 主要产出                                                      |
| ------------ | ----------------------------------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------- |
| `CodeChange` | `azure-pipelines-ci.yml`                                                      | 无                                           | `CDPkgVersion`、`defaultPipelineConfig`                       |
| `PKG`        | `pipeline.json`、两个 `.nuspec`、`deploy/**`、`CustomizeValues.ps1`、解决方案 | `CodeChange` 输出变量                        | 主服务 nupkg、IntegrationTests nupkg、Artifact `pkg`、UT 结果 |
| `QC`         | `pipeline.json`                                                               | `CodeChange` 输出变量、`PKG` 扫描输出        | 质量检查结果、可选 code metrics 摘要                          |
| `Image`      | `Dockerfile`、项目文件、源码                                                  | `CodeChange` 输出变量、`PKG` 的 `PkgVersion` | ACR 镜像                                                      |
| `Deploy`     | 通过主服务 nupkg 间接消费 `deploy/**`、`CustomizeValues.ps1`                  | `pkg` Artifact、`Image` 对应版本镜像         | AKS 部署、渲染后的 values 文件                                |
| `IT`         | IntegrationTests `.nuspec`、`pipeline.json`                                   | `pkg` Artifact、已部署环境                   | IT `.trx`                                                     |
| `FIT`        | `pipeline.json`                                                               | 已部署环境、上游版本信息                     | FIT `.trx` 或跳过结果                                         |
| `Publish`    | `pipeline.json`                                                               | 上游版本信息                                 | 发布 JSON、Blob 记录                                          |

## 6. 对 HydraulicsTransient 改造最有用的结论

从 `RtRheology` 这个参考项目可以提炼出以下约束：

1. `PKG` 阶段必须能同时产出主服务包和 IntegrationTests 包
2. 主服务 `.nuspec` 必须把 `deploy/**` 和 `CustomizeValues.ps1` 打进包中
3. `Image` 阶段直接依赖仓库根目录 `Dockerfile`
4. `Deploy` 阶段不是直接用仓库里的 Chart，而是使用 `pkg` Artifact 中 NuGet 包内的 Chart
5. `IT` 阶段不是重新编译测试，而是安装 IntegrationTests NuGet 包后执行
6. `FIT` 和 `Publish` 是否真的跑额外测试，受 `pipeline.json` 配置控制
7. 若要排查部署问题，优先检查：
   - `pipeline.json`
   - 主服务 `.nuspec`
   - IntegrationTests `.nuspec`
   - `Dockerfile`
   - `deploy/values.yaml`
   - `deploy/templates/*.yaml`
   - `CustomizeValues.ps1`

## 7. 样本运行关键信息

为便于对照，样本运行 `15507955` 的关键结果如下：

| 项目              | 值                                                                               |
| ----------------- | -------------------------------------------------------------------------------- |
| CD 包版本         | `2.192.0`                                                                        |
| 服务包版本        | `2.0.0-ci.15507955`                                                              |
| 主服务包          | `Slb.Prism.Rhapsody.Service.RtRheology.2.0.0-ci.15507955.nupkg`                  |
| 测试包            | `Slb.Prism.Rhapsody.Service.RtRheology.IntegrationTests.2.0.0-ci.15507955.nupkg` |
| Pipeline Artifact | `pkg`                                                                            |
| 镜像              | `drillops.azurecr.io/rhapsody/rtrheology:2.0.0-ci.15507955`                      |
| Helm release      | `rtrheology-2`                                                                   |
| 发布服务名        | `slb.prism.rhapsody.service.rtrheology-2`                                        |
| IT 结果           | `Passed: 1`                                                                      |
| FIT 结果          | 跳过                                                                             |
| Publish 结果      | 上传 `2.0.0-ci.15507955.json` 到 Blob                                            |

## 8. 图

### 宏观

:::mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "fontFamily": "Segoe UI",
    "fontSize": "18px",
    "primaryColor": "#EAF3FF",
    "primaryTextColor": "#16324F",
    "primaryBorderColor": "#4A90E2",
    "lineColor": "#6B7C93",
    "secondaryColor": "#F4F7FB",
    "tertiaryColor": "#EEF6F0"
  }
}}%%

flowchart LR
    subgraph IN["Inputs"]
        I1["Pipeline Entry<br/>azure-pipelines-ci.yml"]
        I2["Pipeline Config<br/>pipeline.json"]
        I3["Packaging & Deploy<br/>*.nuspec, deploy/**, CustomizeValues.ps1"]
        I4["Container Build<br/>Dockerfile"]
    end

    CC["CodeChange"] --> PKG["PKG"] --> QC["QC"] --> IMG["Image"] --> DEP["Deploy"] --> IT["IT"] --> FIT["FIT"] --> PUB["Publish"]

    subgraph OUT["Outputs"]
        O1["CD Package Context<br/>CDPkgVersion"]
        O2["Build Package<br/>pkg artifact + PkgVersion"]
        O3["Container Image<br/>ACR image"]
        O4["Deployment Result<br/>Helm release"]
        O5["Verification & Record<br/>trx / publish json"]
    end

    I1 --> CC
    I2 --> PKG
    I2 --> QC
    I2 --> IT
    I2 --> FIT
    I2 --> PUB
    I3 --> PKG
    I3 --> DEP
    I4 --> IMG

    CC --> O1
    PKG --> O2
    IMG --> O3
    DEP --> O4
    IT --> O5
    FIT --> O5
    PUB --> O5

    O1 -.-> PKG
    O2 -.-> DEP
    O2 -.-> IT
    O3 -.-> DEP
    O4 -.-> IT
    O4 -.-> FIT

    classDef input fill:#F7F9FC,stroke:#7B8BA3,color:#243447,stroke-width:1.2px;
    classDef stage fill:#EAF3FF,stroke:#4A90E2,color:#16324F,stroke-width:1.6px;
    classDef output fill:#EEF6F0,stroke:#58A06A,color:#173A22,stroke-width:1.2px;

    class I1,I2,I3,I4 input;
    class CC,PKG,QC,IMG,DEP,IT,FIT,PUB stage;
    class O1,O2,O3,O4,O5 output;
:::

### 带明细

:::mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "fontFamily": "Segoe UI",
    "fontSize": "16px",
    "primaryColor": "#EAF3FF",
    "primaryTextColor": "#16324F",
    "primaryBorderColor": "#4A90E2",
    "lineColor": "#6B7C93",
    "secondaryColor": "#F7F9FC",
    "tertiaryColor": "#EEF6F0"
  }
}}%%

flowchart LR
    %% Main flow
    CC["CodeChange"] --> PKG["PKG"]
    CC --> QC["QC"]
    CC --> IMG["Image"]
    CC --> DEP["Deploy"]
    CC --> IT["IT"]
    CC --> FIT["FIT"]
    CC --> PUB["Publish"]

    PKG --> QC
    PKG --> IMG
    PKG --> DEP
    PKG --> IT
    PKG --> FIT
    PKG --> PUB

    QC --> IMG
    IMG --> DEP
    DEP --> IT
    IT --> FIT
    FIT --> PUB

    %% Repository inputs
    subgraph REPO["Repository Inputs"]
        YML["azure-pipelines-ci.yml"]
        PJSON["pipeline.json"]
        NUSPEC["*.nuspec"]
        DOCKER["Dockerfile"]
        CHART["deploy/**"]
        CUSTOM["CustomizeValues.ps1"]
    end

    %% Outputs
    subgraph OUT["Key Outputs / Artifacts"]
        CDV["CDPkgVersion<br/>defaultPipelineConfig"]
        PKGA["pkg artifact"]
        PKGV["PkgVersion"]
        IMAGE["ACR image"]
        HELM["Helm release<br/>rendered values"]
        TRX["UT / IT / FIT trx"]
        META["publish json"]
    end

    %% Input dependencies
    YML --> CC
    PJSON --> PKG
    PJSON --> QC
    PJSON --> IT
    PJSON --> FIT
    PJSON --> PUB

    NUSPEC --> PKG
    DOCKER --> IMG
    CHART --> PKG
    CUSTOM --> PKG
    CHART --> DEP
    CUSTOM --> DEP

    %% Output dependencies
    CC --> CDV
    CDV -.-> PKG
    CDV -.-> QC
    CDV -.-> IMG
    CDV -.-> DEP
    CDV -.-> IT
    CDV -.-> FIT
    CDV -.-> PUB

    PKG --> PKGA
    PKG --> PKGV
    PKG --> TRX

    PKGA -.-> DEP
    PKGA -.-> IT
    PKGV -.-> IMG
    PKGV -.-> DEP
    PKGV -.-> IT
    PKGV -.-> FIT
    PKGV -.-> PUB

    IMG --> IMAGE
    IMAGE -.-> DEP

    DEP --> HELM
    HELM -.-> IT
    HELM -.-> FIT

    IT --> TRX
    FIT --> TRX
    PUB --> META

    classDef input fill:#F7F9FC,stroke:#7B8BA3,color:#243447,stroke-width:1.2px;
    classDef stage fill:#EAF3FF,stroke:#4A90E2,color:#16324F,stroke-width:1.6px;
    classDef output fill:#EEF6F0,stroke:#58A06A,color:#173A22,stroke-width:1.2px;

    class YML,PJSON,NUSPEC,DOCKER,CHART,CUSTOM input;
    class CC,PKG,QC,IMG,DEP,IT,FIT,PUB stage;
    class CDV,PKGA,PKGV,IMAGE,HELM,TRX,META output;
:::

## 9. 单一 Actor 与 Actor+Worker 的 Pipeline 对比

本文补充对比以下两类样本：

- 单一 Actor：`Rhapsody.Computation.RtRheology`
- Actor+Worker：`Rhapsody.Computation.HydraulicsTransient`

结论先行：

- 两者使用的是同一个 Pipeline 模板：`tpl-InternalImageDotNetCloud.yml`
- 展开后的 stage 链路相同，仍然是 `CodeChange -> PKG -> QC -> Image -> Deploy -> IT -> FIT -> Publish`
- 真正导致执行差异的，不是 stage 编排，而是仓库中的 Dockerfile 命名、Helm Chart 结构、`values.yaml` 结构，以及这些文件被 CD 包和 Helm 消费的方式

## 10. 差异总表

| 对比项                 | 单一 Actor                                                                               | Actor+Worker                                                                 | 差异原因                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Pipeline 模板          | `InternalImageDotNetCloud`                                                               | `InternalImageDotNetCloud`                                                   | 模板相同                                                    |
| Stage 链路             | 8 个 stage，固定链路                                                                     | 8 个 stage，固定链路                                                         | 模板相同                                                    |
| 入口 YAML              | 额外声明了 `actionForDiffVersion`、`actionForSameVersion`、定时触发、`WindowsAgent` 覆盖 | 入口更精简                                                                   | 这些是参数/调度差异，不是 Actor 与 Worker 模式差异的根因    |
| `pipeline.json` `type` | `InternalImageDotNetCloud`                                                               | `InternalImageDotNetCloud`                                                   | 相同                                                        |
| 镜像构建输入           | 仓库根目录单个 `Dockerfile`                                                              | `Dockerfile-webapi`、`Dockerfile-worker`，日志里还额外构建 `DockerfileLocal` | 镜像脚本会按命名约定扫描并构建                              |
| Image 阶段产物         | 1 个主镜像                                                                               | 至少 2 个运行镜像：`*-webapi`、`*-worker`                                    | Worker 需要独立容器镜像                                     |
| Helm Chart 结构        | 单一 Chart                                                                               | 主 Chart + `deploy/charts/worker` 子 Chart                                   | Worker 通过子 Chart 单独部署                                |
| `values.yaml` 结构     | 只有主服务 `image`、`environmentVariables` 等                                            | 同时包含顶层服务和 `worker.*` 配置                                           | Deploy 时需要同时给 actor 和 worker 注值                    |
| Helm 命令              | 都会带 `--set worker.envType=dev`                                                        | 都会带 `--set worker.envType=dev`                                            | 模板统一传参，但只有 Actor+Worker Chart 真正消费 `worker.*` |
| Deploy 最终效果        | 1 份主服务工作负载                                                                       | 主服务 + worker 两套工作负载                                                 | Helm Chart 结构不同                                         |
| IT/FIT/Publish         | 流程一致                                                                                 | 流程一致                                                                     | 测试与发布链路不因是否有 Worker 而改变                      |

## 11. 关键差异拆解

### 11.1 模板没有变，变的是仓库契约

两个样本展开后的 YAML 几乎一致，stage 名称、依赖关系、下载 `pkg` Artifact 的方式都相同。

因此可以判断：

- 单一 Actor 和 Actor+Worker 在 Pipeline 编排层面没有分叉
- 差异来自仓库内文件如何被共享脚本识别和消费

这也解释了为什么只看 `azure-pipelines-ci.yml` 会觉得“差不多”，但实际执行结果明显不同。

### 11.2 Dockerfile 名称为什么不同

从日志可以看到：

- 单一 Actor 的 `Image` 阶段读取的是 `Dockerfile`
- Actor+Worker 的 `Image` 阶段先后构建：
  - `Dockerfile-webapi`
  - `Dockerfile-worker`

这说明共享 image 脚本不是靠 `pipeline.json` 显式写死“这是单 Actor 还是 Actor+Worker”，而是主要根据仓库中的 Dockerfile 命名约定来决定要构建哪些镜像。

可以归纳为：

- 当仓库只有 `Dockerfile` 时，流水线按单镜像服务处理
- 当仓库存在 `Dockerfile-webapi` 和 `Dockerfile-worker` 时，流水线会把它识别成多组件服务，分别构建 actor/webapi 与 worker 镜像
- `DockerfileLocal` 会被额外构建为本地调试镜像，但不参与正式 Helm 部署

所以“这两类工程在 pipeline 中采用的 dockerfile 名称不同”这件事，本身就是平台识别多组件部署形态的重要依据之一。

### 11.3 Image 阶段的实际差异

单一 Actor 样本 `RtRheology` 的日志显示：

- 从 `Dockerfile` 构建
- 推送镜像 `drillops.azurecr.io/rhapsody/rtrheology:<tag>`

Actor+Worker 样本 `HydraulicsTransient` 的日志显示：

- 从 `Dockerfile-webapi` 构建 `rhapsody/hydraulicstransient-webapi:<tag>`
- 从 `Dockerfile-worker` 构建 `rhapsody/hydraulicstransient-worker:<tag>`
- 还构建 `rhapsody/hydraulicstransient-local:<tag>`

因此 `Image` 阶段的本质差异是：

- 单一 Actor 只生成一个正式运行镜像
- Actor+Worker 会生成多个镜像，至少包含 actor/webapi 镜像和 worker 镜像

### 11.4 Deploy 阶段为什么会不一样

两类工程的 `Deploy` stage 命令形式看起来相似，都会执行：

- `helm upgrade --install ...`
- 都会附加 `values-1-calculated.yaml`
- 都会附加 `values-2-deployargs.yaml`
- 都会传 `--set envType=dev`
- 都会传 `--set worker.envType=dev`

但 Helm Chart 结构不同，导致最终部署结果不同。

单一 Actor：

- `deploy/Chart.yaml` 只有一个应用 Chart
- `deploy/values.yaml` 没有完整的 `worker` 子配置结构
- 因此最终只会部署主 Actor 服务

Actor+Worker：

- `deploy/Chart.yaml` 声明了 `dependencies`
- 依赖本地子 Chart：`file://charts/worker`
- `deploy/charts/worker/templates/deployment.yaml` 会单独生成 worker Deployment
- 顶层 `deploy/templates/deployment.yaml` 则生成 actor/webapi Deployment

所以虽然 `Deploy` 命令长得差不多，真正被 Helm 渲染出来的 Kubernetes 资源数量并不一样：

- 单一 Actor：1 套主服务资源
- Actor+Worker：主服务资源 + worker 资源

### 11.5 为什么日志里两边都有 `worker.envType`

这是一个容易误判的点。

日志显示，即使是单一 Actor，Helm 命令里也带了：

- `--set worker.envType=dev`

但单一 Actor 的 Chart 没有对应 worker 子 Chart 或完整 worker 模板，因此这个参数通常只是“统一模板下的冗余输入”，不会产生额外工作负载。

Actor+Worker 则不同：

- 顶层 `values.yaml` 明确包含 `worker` 节点
- `deploy/charts/worker/**` 会实际消费 `worker.image`、`worker.envType`、`worker.resources` 等配置

因此同样的命令参数，在两类工程里实际效果不同。

### 11.6 Package、IT、Publish 的差异其实很小

从日志看，两类工程在以下方面基本一致：

- `PKG` 都会打主服务包和 `IntegrationTests` 包
- `Deploy` 都是先下载 `pkg` Artifact，再从 nupkg 内取 `deploy/`
- `IT` 都是安装 `IntegrationTests` nupkg 后执行 `vstest.console.exe`
- `FIT` 都跑同样的占位/条件执行逻辑
- `Publish` 都按版本生成发布元数据

说明是否包含 Worker，并不会改变“测试包怎么安装”“发布记录怎么写”这条主链路。

### 11.7 真正导致差异的文件清单

如果要判断一个服务最终会按“单一 Actor”还是“Actor+Worker”执行，优先检查这些文件：

- `Dockerfile`
- `Dockerfile-webapi`
- `Dockerfile-worker`
- `deploy/Chart.yaml`
- `deploy/values.yaml`
- `deploy/charts/worker/**`
- `pipeline.json`
- `*.nuspec`

判断逻辑可以总结为：

- 只有单个 `Dockerfile`，且 Chart 只有一个主服务，一般就是单一 Actor
- 同时存在 `Dockerfile-webapi`、`Dockerfile-worker`，并且 Chart 里有 `worker` 子 Chart，一般就是 Actor+Worker

## 12. 对 HydraulicsTransient 改造最有用的补充结论

相对 `RtRheology`，`HydraulicsTransient` 不是“换了另一套 Pipeline”，而是在同一套 Pipeline 下引入了多组件部署契约：

1. `Image` 阶段必须能识别并构建多个 Dockerfile
2. 主 Chart 需要负责 actor/webapi，子 Chart 需要负责 worker
3. 顶层 `values.yaml` 必须保留 `worker.*` 配置结构，供 CD 和 Helm 覆盖
4. `deploy/charts/worker/templates/deployment.yaml` 中的镜像命名必须与 Image 阶段生成的 `*-worker` 镜像一致
5. 主模板中的镜像命名必须与 `*-webapi` 镜像一致
6. 即使 stage 链路相同，部署出来的资源拓扑也会因为 Helm Chart 结构不同而不同

## 13. 从日志还原的 Values 覆盖层次

基于 `RtRheology` 与 `HydraulicsTransient` 的 `Deploy` 日志，可以还原出部署时实际存在的 values 覆盖链路。

结论先行：

- 日志里明确出现了 3 个运行时生成文件：
  - `values-1-calculated.yaml`
  - `values-2-deployargs.yaml`
  - `values-3-customized.yaml`
- 最终真正传给 Helm 的只有 2 个文件：
  - `-f values-1-calculated.yaml`
  - `-f values-2-deployargs.yaml`
- 如果把包内默认值和命令行 `--set` 也算进来，则本次部署实际有 4 层生效输入：
  1. `deploy/values.yaml`
  2. `values-1-calculated.yaml`
  3. `values-2-deployargs.yaml`
  4. `--set envType=dev --set worker.envType=dev`

其中：

- `values-3-customized.yaml` 被生成了
- 但两个样本日志都显示它是空文件
- 并且最终 `helm upgrade --install` 命令没有带 `-f values-3-customized.yaml`
- 因此这次运行中它没有实际参与 Helm 合并

### 13.1 证据

两个样本的 Deploy 日志都出现了以下顺序：

1. 先运行 `CustomizeValues.ps1`
2. 生成 `values-3-customized.yaml`
3. 打印 `values-1-calculated.yaml`
4. 打印 `values-2-deployargs.yaml`
5. 执行 `helm upgrade --install ... -f values-1-calculated.yaml -f values-2-deployargs.yaml`

并且日志里明确写了：

- `Empty customized values for ...`

所以可以判断：

- 平台预留了“自定义 values”这一层
- 但这两个样本当前都没有真正向这层写入内容

### 13.2 第 1 层：包内默认值 `deploy/values.yaml`

这一层来自服务 NuGet 包中的 Helm Chart 默认值，也就是仓库里的：

- `deploy/values.yaml`

它定义的是服务自身的默认配置。常见内容包括：

- `image`
- `replicaCount`
- `service`
- `environmentVariables`
- `enableDapr`
- `resources`
- `affinity`
- `tolerations`

Actor+Worker 场景下还会额外定义：

- `worker.image`
- `worker.replicaCount`
- `worker.environmentVariables`
- `worker.resources`
- `worker.affinity`
- `worker.containerPort`

这一层的特点是：

- 它是 Chart 自带的默认值
- 不包含当前部署环境计算出来的镜像 tag、环境变量、资源补丁等运行时信息

### 13.3 第 2 层：运行时计算值 `values-1-calculated.yaml`

这是 Deploy 阶段由 CD 平台按环境和服务元数据动态生成的 values 文件。

从日志中可以直接看到它会覆盖的典型内容有：

- `image.repository`
- `image.tag`
- `environmentVariables`
- `replicaCount`
- `affinity`
- `tolerations`
- `ingress.enabled`
- `enableDapr`
- `envType`
- `secretRef`

对单一 Actor 样本 `RtRheology`，日志中可见的关键字段包括：

- `image.repository: drillops.azurecr.io/rhapsody/rtrheology`
- `image.tag: 2.0.0-ci.15507955`
- `environmentVariables.env = intrhapsody`
- `environmentVariables.consulUri = https://13.91.47.250`
- `replicaCount: 2`
- `enableDapr: true`
- `ingress.enabled: false`

对 Actor+Worker 样本 `HydraulicsTransient`，除了主服务字段外，日志还出现了完整的 `worker` 节点，例如：

- `worker.image.repository: drillops.azurecr.io/rhapsody/hydraulicstransient`
- `worker.image.tag: 2.0.0-dapr-ci.15458693`
- `worker.environmentVariables`
- `worker.replicaCount`
- `worker.containerPort: 8080`
- `worker.affinity`
- `worker.resources`

这说明 `values-1-calculated.yaml` 在 Actor+Worker 模式下不是只算一套主服务值，而是会同时准备主服务和 worker 两套运行时覆盖值。

### 13.4 第 3 层：部署参数值 `values-2-deployargs.yaml`

这是部署参数层，主要承接环境补丁或 deploy args。

从两个样本日志里最稳定、最明确的内容是资源配置：

- `resources.limits`
- `resources.requests`

Actor+Worker 样本中还会有：

- `worker.resources.limits`
- `worker.resources.requests`

从当前样例重建文件可以看到一个典型结构：

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 10m
    memory: 128Mi
worker:
  resources:
    limits:
      cpu: 250m
      memory: 512Mi
    requests:
      cpu: 10m
      memory: 128Mi
```

因此这一层可以理解为：

- 基于环境或部署策略，对资源等部署参数进行显式覆盖

### 13.5 第 4 层：命令行 `--set`

最终 Helm 命令里还能看到一层最高优先级覆盖：

- `--set envType=dev`
- `--set worker.envType=dev`

这层的特点是：

- 不通过文件，而是直接写在 Helm 命令行里
- 优先级高于前面的 `values.yaml`、`values-1-calculated.yaml` 和 `values-2-deployargs.yaml`

需要注意的是：

- 单一 Actor 场景下，命令里仍然会统一传 `worker.envType`
- 但如果 Chart 本身不消费 `worker.*`，这个值不会带来额外资源变化
- Actor+Worker 场景则会被 `worker` 子 Chart 实际消费

### 13.6 `values-3-customized.yaml` 的定位

日志显示这层来自：

- `CustomizeValues.ps1`

也就是服务仓库留给项目自身的最后一个扩展点。

但在这两个样本中：

- 日志都写明 `Empty customized values`
- 最终 Helm 命令没有 `-f values-3-customized.yaml`

因此这次可以得出较强结论：

- 平台支持第 5 个候选层次，即“项目自定义 values”
- 但这两个样本本次运行没有启用它

如果未来 `CustomizeValues.ps1` 真正写入了内容，那么它大概率会成为部署前的最后一个服务级补丁层。

### 13.7 本次样本里可确认的最终覆盖顺序

按优先级从低到高，可以整理为：

1. `deploy/values.yaml`
2. `values-1-calculated.yaml`
3. `values-2-deployargs.yaml`
4. `--set envType=dev --set worker.envType=dev`

本次未生效但被创建的候选层：

5. `values-3-customized.yaml`

### 13.8 对排查问题最有用的结论

如果部署结果与仓库里的 `deploy/values.yaml` 不一致，优先按以下顺序排查：

1. 先看 Deploy 日志里打印出来的 `values-1-calculated.yaml`
2. 再看 `values-2-deployargs.yaml`
3. 再看 Helm 命令里的 `--set`
4. 最后确认 `CustomizeValues.ps1` 是否真的写出了 `values-3-customized.yaml`

原因是：

- `deploy/values.yaml` 只是默认值
- 实际部署生效值更接近“默认值 + 运行时计算值 + 部署参数值 + 命令行覆盖”
- 对 Actor+Worker 来说，还必须同时检查顶层字段和 `worker.*` 字段是否都被正确覆盖

## 14. 从日志可确认使用了哪些脚本

基于两个样本的展开 YAML 和运行日志，可以把本次 Pipeline 实际使用到的脚本分成两类：

- 平台共享脚本
- 服务仓库自带脚本

结论先行：

- 大部分 stage 的核心逻辑并不写在仓库里，而是委托给平台脚本 `c:\pipeline\go.ps1` 或 `/opt/pipeline/go_linux.ps1`
- 服务仓库里真正被 Deploy 阶段直接执行的自定义脚本，当前明确能看到的是 `CustomizeValues.ps1`
- Deploy 完成后，还会触发 CD 包里的后处理脚本 `PostDeploy-RegisterServiceToKong.ps1`

### 14.1 平台共享脚本

#### `c:\pipeline\go.ps1`

这是 Windows agent 上的主执行脚本。

从展开后的 YAML 和日志可以确认，下列 stage/job 都是通过它执行的：

- `CodeChange`
- `ut`
- `codescan`
- `pkg`
- `qc`
- `deploy`
- `it`
- `fit`
- `publish`

日志中的典型命令形式如下：

```powershell
. 'c:\pipeline\go.ps1' -task CodeChange -env cloud -taskArgs @{...}
. 'c:\pipeline\go.ps1' -task ut -env cloud
. 'c:\pipeline\go.ps1' -task pkg -env cloud -taskArgs @{...}
. 'c:\pipeline\go.ps1' -task deploy -env cloud -taskArgs @{...}
. 'c:\pipeline\go.ps1' -task it -env cloud
. 'c:\pipeline\go.ps1' -task fit -env cloud
. 'c:\pipeline\go.ps1' -task publish -env cloud -taskArgs @{...}
```

可以理解为：

- 绝大多数构建、打包、部署、测试、发布动作，都是 `go.ps1` 根据 `-task` 参数分发执行的

#### `/opt/pipeline/go_linux.ps1`

这是 Linux agent 上的镜像构建脚本。

在两个样本中，它都只用于 `Image` stage：

```powershell
/opt/pipeline/go_linux.ps1 -task image -env cloud -taskArgs @{...}
```

可以理解为：

- 与镜像构建相关的识别 Dockerfile、构建镜像、推送镜像等逻辑，主要由这个 Linux 侧平台脚本承载

#### Pipeline 中的 inline PowerShell

除了共享脚本外，展开后的 YAML 里还有少量 `targetType: "inline"` 的内联 PowerShell，主要用于：

- `Process Parameters`
  - 选择 `CDPkgVersion`
  - 设置 `defaultPipelineConfig`
  - 写构建摘要
- `Display Package Version Information`
  - 更新 build number
  - 输出包版本摘要
- `Display Code Metrics`
  - 读取 `pipeline.json`
  - 追加 code metrics 摘要

这些 inline 脚本负责参数整理和摘要输出，但不是主要业务执行入口。

### 14.2 CD 包和默认配置文件

从日志还能看出，`go.ps1` / `go_linux.ps1` 在执行时会继续依赖 CD 包里的默认配置文件，例如：

- `C:\Pipeline\default.stable.json`
- `C:\Pipeline\default.latest.json`

日志里多次出现：

- `Default pipeline config file is C:\Pipeline\default.latest.json`
- `Default pipeline config file is C:\Pipeline\default.stable.json`

这说明：

- 平台脚本在执行具体任务时，会再读取默认 CD 配置
- 因此很多行为并不是只由仓库中的 `pipeline.json` 决定，而是 `pipeline.json + default.*.json + 平台脚本` 共同决定

### 14.3 服务仓库自带脚本

#### `CustomizeValues.ps1`

这是当前服务仓库中最明确参与 Deploy 的自定义脚本。

日志里可见它在 `Deploy` 阶段被明确调用：

```text
Run Customize Value Script: ...\CustomizeValues.ps1 <chartPath> <values-3-customized.yaml> ...
```

当前 `HydraulicsTransient` 仓库中的实现非常简单：

- 只输出一行 `Empty customized values ...`
- 不真正写入自定义 values

也就是说，本次样本里它的作用是：

- 占位
- 保持与平台 CD 约定兼容
- 为未来增加自定义 values 留扩展点

### 14.4 Deploy 后处理脚本

#### `PostDeploy-RegisterServiceToKong.ps1`

在两个样本的 Deploy 日志里，都能看到部署完成后执行了：

- `PostDeploy-RegisterServiceToKong.ps1`

结合后续日志可知，这一步会：

- 读取部署后的 values 内容
- 克隆 `rcis-env-int`
- 尝试把服务注册到 Kong 网关相关配置中

所以这属于：

- 部署后的平台后处理脚本
- 不直接参与 Helm 渲染
- 但参与部署完成后的网关发布动作

### 14.5 从日志能确认的脚本清单

本次样本里，明确可从日志确认被执行的脚本包括：

1. `c:\pipeline\go.ps1`
2. `/opt/pipeline/go_linux.ps1`
3. `CustomizeValues.ps1`
4. `PostDeploy-RegisterServiceToKong.ps1`

另外还能确认被读取或间接使用的配置文件包括：

1. `C:\Pipeline\default.stable.json`
2. `C:\Pipeline\default.latest.json`

### 14.6 对排查最有用的理解

如果后续要排查“为什么 Pipeline 会这样执行”，可以按下面的优先级理解脚本职责：

1. 先看展开后的 YAML，确认 stage 调用的是哪个脚本
2. Windows 侧大多数任务看 `go.ps1`
3. 镜像构建看 `go_linux.ps1`
4. Deploy 阶段服务级特殊逻辑看 `CustomizeValues.ps1`
5. 部署完成后的网关动作看 `PostDeploy-RegisterServiceToKong.ps1`

这也意味着：

- 仓库里的 `azure-pipelines-ci.yml` 主要负责“调哪个平台脚本”
- 平台脚本负责“怎么执行”
- 服务仓库脚本只负责少量服务级扩展点
