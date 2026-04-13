请把当前仓库的“统一包版本升级”工作按最稳妥方案拆成多个 agent 分阶段执行，但先只做脚本和文档阶段，不要直接迁移业务仓库。

工作目录：`D:\SLB\Prism\PA`

总体目标：
- 基于现有计划文档，先完成统一包版本升级所需的脚本、README 说明、scripts 文档、基线文档模板、跟踪文档模板
- 所有步骤都要收敛到“可单独 commit”的粒度
- 优先降低冲突和返工风险，而不是追求最大并行度
- 最终需要把各 agent 的成果整合到同一条主线上

执行方式：
- 你可以自行决定是否创建分支
- 如果你认为开分支更稳妥，可以创建 `codex/uni-pkg-version-*` 形式的工作分支
- 但不要一开始就创建很多分支；只有在 agent 需要独立修改文件且可能冲突时再创建
- 最终必须把结果整合回当前工作线程的统一成果中
- 不要做 destructive git 操作
- 不要改动业务仓库代码，除非我后续明确要求进入迁移阶段

请先阅读并遵循这些文档：
- `D:\SLB\Prism\PA\AGENTS.md`
- `D:\SLB\Prism\PA\tasks\task-5-uni-pkg-version.md`
- `D:\SLB\Prism\PA\tasks\uni-pkg-version-plan.md`
- `D:\SLB\Prism\PA\tasks\uni-pkg-version-execution-checklist.md`
- `D:\SLB\Prism\PA\doc\scripts.md`
- `D:\SLB\Prism\PA\README.md`

采用“最稳妥”的 agent 划分，只做下面 4 个方向：

Agent A：目标版本基线脚本
负责：
- 实现 `scripts/export-package-target-baseline.ps1`

脚本功能要求：
- 读取 `doc/package-versions.md`
- 识别每个 package 在当前工作区中“已存在的最高版本”
- 支持排除 `task-5` 中明确不纳入本次改造的工程
- 生成 `tasks/uni-pkg-version-target-baseline.md`
- 输出至少包含这些字段：
  - Package Id
  - Current Versions
  - Target Version
  - Source Repositories
  - In Scope
  - Strategy
  - Exception Reason
- 输出格式为 Markdown
- 文本文件必须保持 CRLF

允许修改文件：
- `D:\SLB\Prism\PA\scripts\export-package-target-baseline.ps1`
- `D:\SLB\Prism\PA\README.md`
- `D:\SLB\Prism\PA\doc\scripts.md`
- `D:\SLB\Prism\PA\tasks\uni-pkg-version-target-baseline.md`

不要修改：
- 其他脚本
- 任何业务仓库工程文件

验收要求：
- 脚本可在仓库根目录执行
- 输出 Markdown 结构稳定
- 能正确排除不在范围内的工程
- README 和 scripts 文档有对应说明
- `README.md` 中必须包含这个脚本的使用方法

Agent B：版本冲突分析脚本
负责：
- 实现 `scripts/find-package-version-conflicts.ps1`

脚本功能要求：
- 读取 `doc/package-versions.md`
- 输出当前仍存在多版本并存的包
- 至少展示：
  - Package Id
  - Versions
  - Repository Count
  - Repositories
- 支持后续区分“计划内例外”和“待处理冲突”的扩展设计
- 输出格式优先 Markdown，也可以支持控制台摘要
- 文本文件必须保持 CRLF

允许修改文件：
- `D:\SLB\Prism\PA\scripts\find-package-version-conflicts.ps1`
- `D:\SLB\Prism\PA\README.md`
- `D:\SLB\Prism\PA\doc\scripts.md`

不要修改：
- baseline 文档
- upgrade tracker
- 业务仓库代码

验收要求：
- 能准确找出多版本包
- 输出便于后续人工 review
- README 和 scripts 文档有对应说明
- `README.md` 中必须包含这个脚本的使用方法

Agent C：升级跟踪模板文档
负责：
- 建立 `tasks/uni-pkg-version-upgrade-tracker.md` 模板

文档功能要求：
- 基于现有计划和执行清单
- 至少包含这些列：
  - Repository
  - Batch
  - Type
  - Package Update
  - Build
  - Test
  - Pipeline
  - Produced Version
  - Actor Backfill
  - Risk / Blocker
  - Owner
  - Updated At
- 预填本次纳入范围的仓库
- 能用于后续批次推进和 Pipeline 跟踪
- 文本文件必须保持 CRLF

允许修改文件：
- `D:\SLB\Prism\PA\tasks\uni-pkg-version-upgrade-tracker.md`

不要修改：
- scripts 目录
- README
- 业务仓库代码

验收要求：
- 模板结构清晰
- 可直接用于后续迁移记录
- 仓库范围与 task-5 保持一致

Agent D：主控整合
你自己作为主控 agent 负责：
- 先制定简短计划
- 决定是否需要为 agent 创建独立分支
- 启动上述 agent，并保证它们的写入范围尽量不重叠
- 特别注意：
  - `README.md`
  - `doc/scripts.md`
  这两个文件容易冲突
- 如果你判断多个 agent 会同时修改 `README.md` 或 `doc/scripts.md`，则不要让它们并行修改这两个文件，改由主控统一整合这些文档变更
- 在 agent 完成后审查结果并整合
- 必要时自己补小修复，但不要重做 agent 已完成的工作
- 最后统一执行：
  - CRLF 规范化
  - 基本验证
  - 结果汇总

并行策略要求：
- 优先并行执行 Agent A 和 Agent C
- Agent B 可以并行，但如果会与 README/doc/scripts.md 冲突，请让 Agent B 只专注脚本本身，由主控统一补 `README.md` 和 `doc/scripts.md`
- 不要开启超过 3 个实际写代码的 agent
- 不要让多个 agent 同时修改同一个目标文件

Git / commit 策略：
- 每个成果尽量可独立 commit
- 推荐的最小提交边界：
  1. `export-package-target-baseline.ps1` 及其文档
  2. `find-package-version-conflicts.ps1` 及其文档
  3. `uni-pkg-version-upgrade-tracker.md`
- 是否创建分支由你判断
- 如果创建分支，最终要把各成果整合到一个统一结果中
- 不要提交或推送，除非我后续明确要求
- 但请在最终汇报中说明建议的 commit 切分方式

工作约束：
- 所有文本文件必须使用 CRLF
- 使用 `apply_patch` 做文件编辑
- 优先复用已有脚本风格
- 不要修改业务仓库 `.csproj`、`.nuspec`、`appsettings.json`
- 本轮目标是“脚本与文档基础设施”，不是实际迁移
- 每个新增脚本的使用方法最终必须更新到 `README.md`
- `doc/scripts.md` 也要同步更新对应说明

输出要求：
- 先给出你打算如何分配 agent 和是否开分支的简短说明
- 然后开始执行
- 完成后汇报：
  - 每个 agent 实际改了哪些文件
  - 是否创建了分支
  - 建议如何拆 commit
  - `README.md` 中新增了哪些脚本使用说明
  - 还缺什么才能进入下一阶段（试点迁移）
