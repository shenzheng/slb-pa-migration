# 任务描述

## 工程范围

- **本次升级 Actor 个数**：以仓库根目录 `AGENTS.md` 中「说明 = 本次升级」为准（当前为 **15** 个；与 `### Actors` 表同步）。
- **核对对象**：每个 Actor 仓库 **master** 分支上 **Actor 入口工程** 的 `App.config`，与 **dapr**（或当前升级分支）上对应 **`appsettings.json`**（通常为部署用的 Web/Worker 宿主工程）。

## 是否改 `appsettings.json` 的判定（必须先于改文件）

1. 在 **master** 上打开该 Actor 的 `App.config`。
2. **若不存在** `<appSettings>...</appSettings>` 节点（或节点为空）：**不要**在 `appsettings.json` 中新增或修改 `"AppSettings"` 段；其余 `Logging` / `LoggerSetup` 等按项目既有规范即可。
3. **若存在** `<appSettings>`：再按下方映射把其中的 `<add key="..." value="..."/>` 迁到 `appsettings.json` 的 `"AppSettings"` 中（键名一致，值为字符串形式等）。

**禁止**：在未核对 master `App.config` 的情况下，按「模板」或参考工程给所有 Actor 统一补上 `"AppSettings"`。

## 映射示例

如 `App.config` 如下：

```xml
<appSettings>
  <add key="AlignmentManager.EnableBuffer" value="false"/>
  <add key="EngineContext.EnableRmqBatchReceiver" value="false"/>
</appSettings>
```

则 `appsettings.json` 中对应为：

```json
{
  "AppSettings": {
    "AlignmentManager.EnableBuffer": "false",
    "EngineContext.EnableRmqBatchReceiver": "false"
  },
  "AllowedHosts": "*"
}
```

## 执行方式

- 若需修改：列出 **哪些 Actor**、**master 中 `<appSettings>` 内容**、以及 **拟写入的 `appsettings.json` 片段**。
- **由人工确认**（已与 master 核对）后，再改仓库中的文件。
