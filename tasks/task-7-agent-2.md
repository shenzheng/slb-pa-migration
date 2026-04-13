请继续在 D:\SLB\Prism\PA 按“最稳妥方案”推进统一包版本升级的下一阶段，但仍然不要进入业务仓库迁移。

本轮目标只做试点迁移前的最后一层基础设施，包含 3 个方向：

Agent A：计划内例外清单模板
负责：
- 建立 D:\SLB\Prism\PA\doc\package-version-conflict-exceptions.md

要求：
- 与 scripts/find-package-version-conflicts.ps1 的扩展列兼容
- 至少包含列：
  - Package Id
  - Status
  - Classification
  - Notes
  - Scope
  - Review Owner
  - Last Reviewed At
- 文档中说明什么情况可登记为计划内例外
- 只做模板和说明，不预填大量内容
- 文本必须 CRLF

允许修改文件：
- D:\SLB\Prism\PA\doc\package-version-conflict-exceptions.md

不要修改：
- scripts 目录
- README.md
- 业务仓库代码

Agent B：Pipeline 版本提取脚本
负责：
- 实现 D:\SLB\Prism\PA\scripts\extract-pipeline-package-version.ps1

要求：
- 能从 Azure DevOps 构建标题、日志片段或文本输入中提取类似 #1.0.0.15601898 的真实包版本
- 输出应适合后续被脚本消费
- 支持从文件读取，也支持直接传入字符串
- 至少支持：
  - InputPath
  - Text
  - OutputPath
  - AsJson
- 文本必须 CRLF

允许修改文件：
- D:\SLB\Prism\PA\scripts\extract-pipeline-package-version.ps1

不要修改：
- README.md
- doc/scripts.md
- 业务仓库代码

Agent C：统一验证脚本
负责：
- 实现 D:\SLB\Prism\PA\scripts\verify-package-upgrade.ps1

要求：
- 当前先做“框架版”，不要直接跑所有业务仓库
- 能对指定仓库目录执行基础检查
- 至少支持：
  - dotnet restore
  - dotnet build
  - 可选 test
  - nuspec / project version consistency 的预留检查位
  - CRLF 检查
- 输出结构要便于后续试点迁移使用
- 文本必须 CRLF

允许修改文件：
- D:\SLB\Prism\PA\scripts\verify-package-upgrade.ps1

不要修改：
- README.md
- doc/scripts.md
- 业务仓库代码

主控要求：
- 先制定简短计划
- 继续采用“文件写入范围尽量不重叠”的 agent 划分
- README.md 和 doc/scripts.md 由你主控统一修改，不要让 agent 并行改这两个文件
- agent 完成后审查结果并整合
- 必要时自己补小修复，但不要重做 agent 已完成工作
- 最后统一执行 CRLF 规范化、基本验证、结果汇总

并行策略：
- 优先并行 Agent A 和 Agent B
- Agent C 视冲突情况决定是否并行
- 不要开启超过 3 个实际写代码 agent
- 不要让多个 agent 同时修改同一个文件

Git / commit 策略：
- 不要提交或推送
- 推荐最小 commit 边界：
  1. package-version-conflict-exceptions.md
  2. extract-pipeline-package-version.ps1 及其文档
  3. verify-package-upgrade.ps1 及其文档

输出要求：
- 先说明 agent 分配和是否开分支
- 完成后汇报：
  - 每个 agent 改了哪些文件
  - 建议如何拆 commit
  - README.md 新增了哪些脚本说明
  - 距离试点迁移还差什么
