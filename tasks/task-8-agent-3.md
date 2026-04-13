你负责 Agent A，只能修改一个文件：D:\SLB\Prism\PA\scripts\find-package-version-conflicts.ps1。

任务：在不破坏现有输出的前提下，增强它对 D:\SLB\Prism\PA\doc\package-version-conflict-exceptions.md 的兼容性。当前模板除了核心列 `Package Id / Status / Classification / Notes`，还增加了 `Scope / Review Owner / Last Reviewed At`。你的目标是让脚本“能读取扩展模板，但对旧模板也兼容”。

要求：
- 保持现有默认输出结构稳定
- 允许内部读取扩展元数据
- 如需输出扩展列，必须是向后兼容的最小增量，不要改坏当前消费者
- 不要修改 README.md、doc/scripts.md、业务仓库代码
- 只对你负责的文件做最小必要修改
- 文件必须为 UTF-8 无 BOM，CRLF
- 你不是独自在代码库里工作，不要回滚别人改动

完成后汇报：
- 改了什么
- 是否影响现有输出
- 修改文件路径

你负责 Agent B，只能修改一个文件：D:\SLB\Prism\PA\scripts\extract-pipeline-package-version.ps1。

任务：在保持现有参数 `InputPath / Text / OutputPath / AsJson` 兼容的前提下，把脚本补强为更适合后续自动化链路消费的小工具。

优先方向：
- 明确“未提取到版本”时的退出行为和错误信息
- 确保文件输入、直接文本输入、JSON 输出三种模式都稳定
- 如确有必要，可增加一个很轻量的新参数，但不要破坏现有接口
- 输出仍以“默认纯文本版本号、AsJson 输出结构化对象”为主

不要修改：
- README.md
- doc/scripts.md
- 业务仓库代码

约束：
- 只修改你负责的文件
- UTF-8 无 BOM，CRLF
- 你不是独自在代码库里工作，不要回滚别人改动

完成后汇报：
- 改了什么
- 为什么这样改
- 修改文件路径

你负责 Agent C，只能修改一个文件：D:\SLB\Prism\PA\scripts\verify-package-upgrade.ps1。

任务：在当前“框架版”基础上，补到可服务单仓试点迁移的程度，但仍然不要让脚本默认扫描全部业务仓库。

优先实现：
- 真正的 `nuspec / project version consistency` 基础检查
- 检查 `.nuspec` 中的版本与项目/属性中的版本是否一致，至少输出 `Passed / Failed / Skipped / Reserved` 中合理状态
- 保持现有 `RepositoryPath / RunTest / AsJson / OutputPath` 接口兼容
- JSON 结构尽量稳定，便于后续试点直接消费

不要修改：
- README.md
- doc/scripts.md
- 业务仓库代码

约束：
- 只修改你负责的文件
- UTF-8 无 BOM，CRLF
- 你不是独自在代码库里工作，不要回滚别人改动

完成后汇报：
- 改了什么
- JSON 输出是否有不兼容变化
- 修改文件路径

主控收口顺序

审查 A 的输出是否仍兼容现有冲突报告
审查 B 的错误码和输出稳定性
审查 C 的版本一致性检查是否会误报
必要时补最小修复
最后统一修改 README.md 和 doc/scripts.md
统一做 CRLF 和轻量验证