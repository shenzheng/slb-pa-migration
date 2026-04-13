# ChannelProjection 试点执行清单

生成时间：2026-04-10 03:20

## 目标

为统一包版本升级的首个真实试点做好执行准备，对象为：

- `Shared\Rhapsody.Algorithm.ChannelProjection`
- `Actors\Rhapsody.Computation.ChannelProjection`

本清单只用于试点执行规划，不直接落代码改动。

## 当前阻塞事实

- Shared 仓库可以构建，但外部依赖版本不一致。
- Actor 仓库可以构建，且当前 `nuspec` 未声明依赖，因此依赖一致性检查为 `Skipped`。
- Actor 仓库在 restore/build 时仍有 package feed 和老旧依赖告警，但这不是当前试点的第一阻塞项。

## 正式试点时预计会修改的文件

### Shared 仓库

- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.csproj`
- `Shared\Rhapsody.Algorithm.ChannelProjection\Slb.Prism.Rhapsody.Algorithm.ChannelProjection.nuspec`

说明：

- 只改外部依赖引用版本
- 不改 `.nuspec` 的 `<version>`
- 不改 `.csproj` 的程序集自身版本
- 不改 `SharedAssemblyInfo.cs`

### Actor 仓库

- `Actors\Rhapsody.Computation.ChannelProjection\ComputationActor\Slb.Prism.Rhapsody.Service.ChannelProjectionActor.csproj`

说明：

- Shared 发版后，只回灌 `Slb.Prism.Rhapsody.Algorithm.ChannelProjection` 的真实版本号
- 当前不以修改 actor 自身 `.nuspec` `<version>` 为目标
- 当前不以修改 `SharedAssemblyInfo.cs` 为目标

## Shared 当前需要处理的依赖差异

- `Newtonsoft.Json`
  - `.csproj PackageReference = 13.0.1`
  - `.nuspec metadata/dependencies = 12.0.3`

推荐处理方式：

- 以 `.csproj PackageReference` 为准
- 同步更新 `.nuspec metadata/dependencies`

## Actor 当前需要处理的内容

- 当前不需要修“自身版本真值”
- 当前需要等 Shared 真实产物版本号
- Shared 发版后，回灌：
  - `Actors\Rhapsody.Computation.ChannelProjection\ComputationActor\Slb.Prism.Rhapsody.Service.ChannelProjectionActor.csproj`
  - `Slb.Prism.Rhapsody.Algorithm.ChannelProjection = <Shared 真实版本号>`

## 推荐执行顺序

1. 先修 Shared 仓库的依赖版本一致性。
2. 仅对 Shared 仓库重新执行一次校验。
3. 运行 Shared pipeline，提取真实包版本号。
4. 将 Shared 真实版本号回填到跟踪表。
5. 再修改 Actor 对 Shared 包的引用版本。
6. 仅对 Actor 仓库重新执行一次校验。
7. 运行 Actor pipeline。
8. 将 Actor 真实版本号和 Shared 回灌来源回填到跟踪表。

## 试点后的 pipeline 与回灌顺序

### 阶段 1：先发 Shared

1. 完成 Shared 仓库代码修改。
2. 在 Shared 仓库本地执行校验：
   - `verify-package-upgrade.ps1`
   - 必要时补 `dotnet test`
3. 提交 Shared 仓库改动并运行对应 Azure DevOps pipeline。
4. 等 Shared pipeline 成功后，从构建标题、日志或发布信息中提取真实包版本号。

建议命令：

```powershell
& .\scripts\extract-pipeline-package-version.ps1 `
  -Text '<Azure DevOps 构建标题或日志片段>'
```

或：

```powershell
& .\scripts\extract-pipeline-package-version.ps1 `
  -InputPath .\tasks\shared-channelprojection-pipeline-log.txt `
  -AsJson `
  -OutputPath .\tasks\shared-channelprojection-produced-version.json
```

### 阶段 2：记录 Shared 真实产物版本

拿到 Shared 真实版本号后，至少回填两处：

1. `tasks\uni-pkg-version-upgrade-tracker.md`
   - Shared 对应行：
     - `Pipeline = Done`
     - `Produced Version = <真实版本号>`
2. Actor 试点工作记录
   - 标明“Actor 接下来应引用的 Shared 新版本号”

### 阶段 3：回灌 Actor

Actor 的“回灌”不是回写到 Shared，而是把 Shared 的新真实版本号灌回 Actor 引用。

对于 `ChannelProjection` 试点，回灌动作应是：

1. 修改 actor 项目中对 Shared 算法包的引用版本
   - `Actors\Rhapsody.Computation.ChannelProjection\ComputationActor\Slb.Prism.Rhapsody.Service.ChannelProjectionActor.csproj`
   - 当前引用：
     - `Slb.Prism.Rhapsody.Algorithm.ChannelProjection`
   - 更新为 Shared pipeline 产出的真实版本号
2. 如有 integration test / 其它项目也直接引用该 Shared 包，同步更新
3. 本地重新执行 actor 校验
4. 提交 actor 改动并运行 actor 对应 pipeline

### 阶段 4：获得 Actor 新版本号并完成回填

1. 等 actor pipeline 成功。
2. 用 `extract-pipeline-package-version.ps1` 提取 actor 真实产物版本号。
3. 回填 `tasks\uni-pkg-version-upgrade-tracker.md`
   - Actor 对应行：
     - `Pipeline = Done`
     - `Produced Version = <actor 真实版本号>`
     - `Actor Backfill = Shared <shared 真实版本号>`

## 试点执行时的验证命令

### 仅验证 Shared

```powershell
& .\scripts\verify-package-upgrade.ps1 `
  -RepositoryPath .\Shared\Rhapsody.Algorithm.ChannelProjection `
  -RunTest `
  -AsJson `
  -OutputPath .\tasks\verify-channelprojection-shared.json
```

### 仅验证 Actor

```powershell
& .\scripts\verify-package-upgrade.ps1 `
  -RepositoryPath .\Actors\Rhapsody.Computation.ChannelProjection `
  -RunTest `
  -AsJson `
  -OutputPath .\tasks\verify-channelprojection-actor.json
```

### 成对验证

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

## 进入真实迁移前的通过条件

- Shared `DependencyConsistency = Passed`
- Actor `DependencyConsistency = Passed` 或 `Skipped`
- Shared `restore/build/test = Passed`
- Actor `restore/build/test = Passed`
- 不引入新的 CRLF 问题
- 若仍有残余警告，需明确记录为试点可接受的非阻塞项

## 首个试点的非目标

- 不先处理掉所有依赖漏洞告警
- 不在这一轮直接推广到 Batch 1 或 Batch 2
- 不在首个试点里顺手重构所有 actor 的 nuspec 依赖声明方式
