# 包版本冲突计划内例外清单

## 用途

本文件用于登记“已确认且被允许暂时保留”的包版本冲突，供 `scripts/find-package-version-conflicts.ps1` 在输出冲突报告时，将“计划内例外”和“待处理冲突”区分开来。

## 何时可以登记

只有在以下条件同时满足时，才可以登记为计划内例外：

- 版本差异是有意保留的，并且已有明确负责人。
- 例外范围是可控的，并且有明确复核时间。
- 该冲突属于当前迁移批次内可接受的暂时状态，不是遗漏或未知漂移。
- 该决策可以用简短说明解释清楚，必要时可关联任务单或评审记录。

以下情况不应登记到本文件：

- 原因尚不明确的版本漂移。
- 仍需分析的问题。
- 只是暂时没处理、但并未正式接受的冲突。

## 兼容性说明

现有冲突脚本优先读取核心列，因此请保持 `Package Id`、`Status`、`Classification`、`Notes` 这四列稳定。

`Scope`、`Review Owner`、`Last Reviewed At` 用于后续 triage、定期复核和清理，可作为扩展元数据维护。

## 模板

### 冲突登记表

| Package Id | Status | Classification | Notes |
| --- | --- | --- | --- |
| `<package-id>` | Planned Exception | `<classification>` | `<简短原因与决策依据>` |

### 复核元数据

| Package Id | Scope | Review Owner | Last Reviewed At |
| --- | --- | --- | --- |
| `<package-id>` | `<仓库或解决方案范围>` | `<负责人>` | `<yyyy-mm-dd>` |

## 维护建议

- 每一行只登记一个 `Package Id`。
- 优先填写可审计、可追踪的简短说明，不要写成长篇背景。
- 每次复核、延续或关闭例外时，都应同步更新 `Last Reviewed At`。
- 当该包不再需要保留例外时，应及时删除对应记录。
