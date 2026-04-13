# ChannelProjection 试点指令

生成时间：2026-04-10 03:20

## 前提

- 本轮不修改 Shared / Actor 两侧 `.nuspec` 的 `<version>`。
- 本轮不修改 `.csproj` / `SharedAssemblyInfo.cs` 中用于程序集自身的版本号。
- 本轮只处理“对其它包引用的版本一致性”：
  - `.csproj` / `Directory.Packages.props` / `packages.config` 中的引用版本
  - `.nuspec` `metadata/dependencies` 中的依赖版本
- Shared 必须先发版，Actor 再回灌 Shared 的真实产物版本号并发版。

## Shared 试点指令

### 1. 修改范围

优先检查以下文件中的外部包引用版本是否一致：

- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.csproj`
- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.nuspec`

当前已确认需要处理的差异：

- `Newtonsoft.Json`
  - `.csproj` 中为 `13.0.1`
  - `.nuspec` `dependencies` 中为 `12.0.3`

建议处理方式：

- 以 `.csproj PackageReference` 为准
- 同步更新 `.nuspec` `metadata/dependencies` 中对应依赖版本

不要修改：

- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.nuspec` 中的 `<version>`
- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.csproj` 中的程序集自身版本号
- `Shared\Rhapsody.Algorithm.ChannelProjection\SharedAssemblyInfo.cs`

### 2. 本地验证

```powershell
& .\scripts\verify-package-upgrade.ps1 `
  -RepositoryPath .\Shared\Rhapsody.Algorithm.ChannelProjection `
  -RunTest `
  -AsJson `
  -OutputPath .\tasks\verify-channelprojection-shared.json
```

通过标准：

- `Restore = Passed`
- `Build = Passed`
- `Test = Passed`
- `CRLF = Passed`
- `DependencyConsistency = Passed`

### 3. 运行 Shared pipeline

- 提交 Shared 仓库改动
- 在 Azure DevOps 中运行 `Rhapsody.Algorithm.ChannelProjection` 对应 pipeline
- 等待 pipeline 成功

### 4. 提取 Shared 真实版本号

```powershell
& .\scripts\extract-pipeline-package-version.ps1 `
  -InputPath .\tasks\shared-channelprojection-pipeline-log.txt `
  -AsJson `
  -OutputPath .\tasks\shared-channelprojection-produced-version.json
```

或：

```powershell
& .\scripts\extract-pipeline-package-version.ps1 `
  -Text '<Shared pipeline 标题或日志片段>'
```

### 5. 回填 Shared 跟踪信息

更新 `tasks\uni-pkg-version-upgrade-tracker.md`：

- `Rhapsody.Algorithm.ChannelProjection`
  - `Pipeline = Done`
  - `Produced Version = <Shared 真实版本号>`

## Actor 试点指令

### 1. 回灌 Shared 新版本

拿到 Shared 真实版本号后，修改 actor 对 Shared 包的引用：

- `Actors\Rhapsody.Computation.ChannelProjection\ComputationActor\Slb.Prism.Rhapsody.Service.ChannelProjectionActor.csproj`

将：

- `Slb.Prism.Rhapsody.Algorithm.ChannelProjection`

更新为：

- `<Shared 真实版本号>`

如其它 actor 侧项目也直接引用该 Shared 包，同步更新。

### 2. 当前不需要修改的内容

- `Actors\Rhapsody.Computation.ChannelProjection\Slb.Prism.Rhapsody.Service.ChannelProjection.nuspec`
  当前没有 `metadata/dependencies`，因此本轮不做依赖一致性修改
- `Actors\Rhapsody.Computation.ChannelProjection\IntegrationTests\Slb.Prism.Rhapsody.Computation.ChannelProjection.IntegrationTests.nuspec`
  当前没有 `metadata/dependencies`，因此本轮不做依赖一致性修改
- `Actors\Rhapsody.Computation.ChannelProjection\SharedAssemblyInfo.cs`

### 3. 本地验证

```powershell
& .\scripts\verify-package-upgrade.ps1 `
  -RepositoryPath .\Actors\Rhapsody.Computation.ChannelProjection `
  -RunTest `
  -AsJson `
  -OutputPath .\tasks\verify-channelprojection-actor.json
```

通过标准：

- `Restore = Passed`
- `Build = Passed`
- `Test = Passed`
- `CRLF = Passed`
- `DependencyConsistency = Passed` 或 `Skipped`
  当前 `Skipped` 的前提是对应 `nuspec` 未声明依赖

### 4. 运行 Actor pipeline

- 提交 Actor 仓库改动
- 在 Azure DevOps 中运行 `Rhapsody.Computation.ChannelProjection` 对应 pipeline
- 等待 pipeline 成功

### 5. 提取 Actor 真实版本号

```powershell
& .\scripts\extract-pipeline-package-version.ps1 `
  -InputPath .\tasks\actor-channelprojection-pipeline-log.txt `
  -AsJson `
  -OutputPath .\tasks\actor-channelprojection-produced-version.json
```

### 6. 回填 Actor 跟踪信息

更新 `tasks\uni-pkg-version-upgrade-tracker.md`：

- `Rhapsody.Computation.ChannelProjection`
  - `Pipeline = Done`
  - `Produced Version = <Actor 真实版本号>`
  - `Actor Backfill = Shared <Shared 真实版本号>`

## 成对复核指令

```powershell
$paths = @(
  '.\Shared\Rhapsody.Algorithm.ChannelProjection',
  '.\Actors\Rhapsody.Computation.ChannelProjection'
)

& .\scripts\verify-package-upgrade.ps1 `
  -RepositoryPath $paths `
  -RunTest `
  -AsJson `
  -OutputPath .\tasks\verify-channelprojection-baseline.json
```

## 通过标准

- Shared `DependencyConsistency = Passed`
- Actor `DependencyConsistency = Passed` 或 `Skipped`
- Shared `Pipeline = Done`
- Actor `Pipeline = Done`
- 跟踪表中的 `Produced Version` 与 `Actor Backfill` 已完成回填
