# 试点依赖一致性规则

生成时间：2026-04-10 03:20

## 目的

本文档用于记录统一包版本升级试点阶段，如何比较以下两类信息：

- 项目中的外部包引用版本
  - `.csproj`
  - `Directory.Packages.props`
  - `Directory.Build.props`
  - `packages.config`
- `.nuspec` `metadata/dependencies` 中的依赖版本

本文档不用于比较以下内容：

- `.nuspec` 的 `<version>`
- `.csproj` 的 `Version` / `PackageVersion`
- `SharedAssemblyInfo.cs` / `AssemblyInfo.cs` 中的程序集版本

## 规则 1：比较对象

对每个可匹配的 `.nuspec` / 项目对，只比较依赖项：

1. 项目侧直接或中心化声明的 `PackageReference`
2. `packages.config` 中的依赖
3. `.nuspec` `metadata/dependencies` 中的 `dependency`

不比较：

1. 包自身 `<version>`
2. 项目自身 `Version`
3. 程序集版本

## 规则 2：nuspec 到项目的匹配顺序

优先顺序如下：

1. 项目文件名 stem 与 nuspec 文件名 stem 完全一致
2. 使用 package id / 文件名变体规则匹配，例如：
   - `Actor`
   - `IntegrationTests`
   - `UnitTests`
   - `Tests`
3. 如果 nuspec 所在目录只有一个项目，则直接使用该项目
4. 如果仍有多个候选，则标记为 `Reserved`

## 规则 3：依赖一致性的判定

### Passed

满足以下条件时判定为 `Passed`：

- `.nuspec` 中声明了依赖
- 对应项目可以解析出可比较的包引用
- 两边依赖集合一致，且相同包 id 的版本一致

### Failed

满足以下任一条件时判定为 `Failed`：

- 同一包 id 在 `.csproj` / props / `packages.config` 与 `.nuspec dependencies` 中版本不同
- 项目里有包引用，但 `.nuspec dependencies` 中缺失
- `.nuspec dependencies` 中有依赖，但项目侧没有对应包引用

### Skipped

满足以下任一条件时判定为 `Skipped`：

- `.nuspec` 没有声明任何 `dependencies`
- 找到了项目，但当前没有可比较的依赖集合
- 没有项目、没有 nuspec，或当前不适合比较

### Reserved

满足以下任一条件时判定为 `Reserved`：

- 一个 `.nuspec` 对应多个项目候选，无法安全自动判断
- `.nuspec` / 项目文件无法稳定解析

## 规则 4：ChannelProjection 当前适用结论

### Shared

- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.csproj`
- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.nuspec`

当前已确认差异：

- `Newtonsoft.Json`
  - 项目侧：`13.0.1`
  - nuspec 侧：`12.0.3`

因此当前应判定为：

- `DependencyConsistency = Failed`

### Actor

- `Actors\Rhapsody.Computation.ChannelProjection\ComputationActor\Slb.Prism.Rhapsody.Service.ChannelProjectionActor.csproj`
- `Actors\Rhapsody.Computation.ChannelProjection\Slb.Prism.Rhapsody.Service.ChannelProjection.nuspec`

当前情况：

- 项目侧存在 `PackageReference`
- 对应 `.nuspec` 当前没有 `metadata/dependencies`

因此当前应判定为：

- `DependencyConsistency = Skipped`

这不等于 actor 无事可做，只表示当前没有“可由该规则自动判失败”的内部依赖不一致项。

## 规则 5：回灌规则仍然保留

即使某个 actor 当前 `DependencyConsistency = Skipped`，在 Shared 发版后仍需要：

1. 提取 Shared 真实产物版本号
2. 回灌 Actor 对 Shared 内部包的 `PackageReference`
3. 重新验证并跑 Actor pipeline
