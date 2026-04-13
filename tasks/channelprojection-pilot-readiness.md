# ChannelProjection 试点准备情况

生成时间：2026-04-10 03:20

## 范围

- Shared：`Shared\Rhapsody.Algorithm.ChannelProjection`
- Actor：`Actors\Rhapsody.Computation.ChannelProjection`
- 基线报告：
  - `tasks\verify-channelprojection-baseline.json`

## 当前基线摘要

| Repository | Restore | Build | Test | CRLF | Dependency Consistency | Summary |
| --- | --- | --- | --- | --- | --- | --- |
| `Shared\Rhapsody.Algorithm.ChannelProjection` | Passed | Passed | Passed | Passed | Failed | 可构建，但存在外部依赖版本不一致 |
| `Actors\Rhapsody.Computation.ChannelProjection` | Passed | Passed | Passed | Passed | Skipped | 可构建；当前 nuspec 未声明依赖，因此该项暂不比较 |

## 已确认的问题

### 1. Shared 仓库存在外部依赖版本不一致

- 项目文件：
  - `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.csproj`
- 打包文件：
  - `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.nuspec`
- 当前已确认差异：
  - `Newtonsoft.Json`
    - `.csproj` 中为 `13.0.1`
    - `.nuspec` `dependencies` 中为 `12.0.3`
- 影响：
  - `verify-package-upgrade.ps1` 现报告 `DependencyConsistency = Failed`
  - 说明 Shared 包的实际编译依赖与发布元数据不一致

### 2. Actor 仓库当前没有“需要立刻修正的内部依赖一致性问题”

- 主项目：
  - `Actors\Rhapsody.Computation.ChannelProjection\ComputationActor\Slb.Prism.Rhapsody.Service.ChannelProjectionActor.csproj`
- 当前内部包引用：
  - `Slb.Prism.Rhapsody.Algorithm.ChannelProjection = 2.0.0.13909616`
- 当前 nuspec 状态：
  - `Actors\Rhapsody.Computation.ChannelProjection\Slb.Prism.Rhapsody.Service.ChannelProjection.nuspec`
  - `Actors\Rhapsody.Computation.ChannelProjection\IntegrationTests\Slb.Prism.Rhapsody.Computation.ChannelProjection.IntegrationTests.nuspec`
  - 两者目前都没有 `metadata/dependencies`
- 当前脚本结论：
  - `DependencyConsistency = Skipped`
  - 原因是“没有可比较的 nuspec dependencies”
- 这意味着：
  - Actor 当前的重点不是修自己 `nuspec` 的 `<version>`
  - 而是在 Shared 发出新包后，回灌 `PackageReference` 的真实版本号

### 3. Actor 仓库 restore/build 仍是“通过但带警告”

- actor 仓库的 `restore` 与 `build` 已通过
- 基线报告中仍观察到以下警告：
  - 多个 Azure DevOps package feed 的 `NU1900`
  - 老版本依赖带来的 `NU1902` / `NU1903`
- 影响：
  - 这不是当前试点的首要阻塞项
  - 但需要记录，避免高估试点环境整洁度

## 结论

在当前口径下，`ChannelProjection` 仍适合作为试点，但试点目标已经收敛为：

1. 先修 Shared 的外部依赖版本一致性
   当前至少需要处理 `Newtonsoft.Json`
2. Shared 发版后，拿真实产物版本号
3. 再把该真实版本号回灌到 Actor 对 `Slb.Prism.Rhapsody.Algorithm.ChannelProjection` 的引用

## 当前不建议处理的内容

- 不修改 Shared / Actor `.nuspec` 的 `<version>`
- 不修改 `.csproj` / `SharedAssemblyInfo.cs` 中用于程序集自身的版本号
- 不把 Actor 当前 `DependencyConsistency = Skipped` 误判为阻塞项
- 不在首个试点里顺手重构所有 actor 的 nuspec 依赖声明方式
