---
name: prism-ado-pipeline-status
description: 查询 Prism 升级相关 Azure DevOps Pipeline 在 dapr（或其它分支）上的最近一次执行状态，并生成指向「最后 Stage」日志视图的链接；使用 AAD（az login），无需 PAT。
---

# Prism 升级 Pipeline 状态（ADO + AAD）

## 何时使用

- 用户询问 **本次升级涉及的 Pipeline 执行情况**、**dapr 分支构建是否成功**、或需要 **每个 Pipeline 的 ADO 链接（含最后 Stage）**。
- 需要 **可重复、可审计** 的回答：优先运行仓库脚本，避免凭记忆或过时表格。

## 前置条件

1. 已安装 **Azure CLI**：<https://aka.ms/installazurecliwindows>
2. 已用 **AAD** 登录（无需 PAT）：

   ```text
   az login
   ```

3. 当前账号对 **Azure DevOps 组织 `slb1-swt`**、项目 **Prism** 有读构建权限。

令牌由脚本内部通过以下方式获取（与手动命令等价）：

```text
az account get-access-token --resource 499b84ac-1321-4277-86b9-215fbc768055
```

## 一键查询（推荐）

在仓库根目录或 `scripts` 目录执行：

```powershell
.\scripts\get-upgrade-pipeline-status.ps1
```

默认：**分支** `refs/heads/dapr`，**Markdown** 表格输出到控制台。

### 常用参数

| 参数                                  | 说明                                                                                         |
| ------------------------------------- | -------------------------------------------------------------------------------------------- |
| `-Branch 'refs/heads/dapr'`           | 指定分支（默认即 dapr）                                                                      |
| `-FallbackAnyBranch`                  | 某定义在指定分支 **无构建** 时，再取 **全分支** 最近一次构建（适合长期未打 dapr 的参考工程） |
| `-SkipTimeline`                       | 不调用 Timeline API，不生成「最后 Stage」深链（更快）                                        |
| `-OutputFormat Json`                  | 输出 JSON（便于保存或再处理）                                                                |
| `-OutFile '.\out\pipeline-status.md'` | 写入文件（UTF-8 BOM）                                                                        |

示例：

```powershell
.\scripts\get-upgrade-pipeline-status.ps1 -FallbackAnyBranch -OutFile .\out\pipeline-status.md
```

## Pipeline 列表来源

定义列表在 `scripts/upgrade-pipeline-definitions.json`，与 `doc/rhapsody-service-to-ado-pipeline-mapping.md` 中的 Definition ID 对齐，并包含参考工程 **DataGenerator / ActorDirector / StreamSampling**。

修改 ID 时：**二处择一为主源**并保持一致，避免脚本与文档漂移。

## 链接含义

- **构建结果**：Azure DevOps 该次 **Run** 的结果页（`_links.web` 或 `buildId`）。
- **最后 Stage 日志**：由 Build **Timeline** 中 `type == Stage` 且 **order 最大** 的记录生成，形如  
  `.../_build/results?buildId=<id>&view=logs&t=<stageRecordGuid>`。  
  若你方 DevOps UI 版本对 query 不兼容，仍以 **构建结果** 链接为准，在页面中手动展开最后 Stage。

## 在对话中如何答得「稳定」

1. 运行上述脚本（或让代理在终端执行并粘贴输出）。
2. 回答时 **不要** 手抄历史 BuildId；若需固定留档，使用 `-OutFile` 生成文件并提交或附在 Wiki。
3. 与 **MCP `pipelines_get_builds`** 相比：脚本额外提供 **最后 Stage 深链** 与 **本地定义列表**；MCP 仍可用于临时抽查单个定义。

## 故障排查

| 现象               | 处理                                                                                |
| ------------------ | ----------------------------------------------------------------------------------- |
| `az` 未找到        | 安装 Azure CLI 并重启终端                                                           |
| 取 token 失败      | 执行 `az login`；必要时 `az account show` 确认订阅/租户                             |
| 全部「无构建」     | 确认分支名是否为 `refs/heads/dapr`；或对冷门 Pipeline 加 `-FallbackAnyBranch`       |
| 无「最后 Stage」列 | 构建过旧或 Timeline 无 `Stage` 记录；试去掉 `-SkipTimeline`；或 YAML 结构与预期不符 |
