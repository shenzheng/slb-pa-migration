# Scripts 使用说明

## 概述

本文档说明 `scripts` 目录下各个 PowerShell 脚本的用途和用法。

## git-pull-all.ps1

`git-pull-all.ps1` 用于拉取 `Actors` 和 `Shared` 目录下各 Git 仓库当前分支的最新版本。

### 脚本行为

- 使用 `git pull --ff-only`，避免自动生成 merge commit。
- 处于 detached `HEAD` 状态的仓库会被跳过。
- 当前分支未配置上游分支的仓库会被跳过。
- 顶层分组目录不存在时会跳过并记录。
- 脚本会输出成功、跳过、失败三类汇总信息。
- 只要有任意仓库拉取失败，脚本会以退出码 `1` 结束。

### 参数

| 参数            | 说明                 | 默认值                     |
| --------------- | -------------------- | -------------------------- |
| `RootPath`      | 仓库根目录路径。     | `scripts` 目录的上一级目录 |
| `ProjectGroups` | 需要扫描的顶层目录。 | `Actors`, `Shared`         |

### 示例

```powershell
.\scripts\git-pull-all.ps1
```

```powershell
.\scripts\git-pull-all.ps1 -RootPath D:\SLB\Prism\PA
```

```powershell
.\scripts\git-pull-all.ps1 -ProjectGroups Actors
```

## normalize-crlf.ps1

`normalize-crlf.ps1` 用于将指定目录下符合条件的文本文件统一转换为 Windows `CRLF` 换行。

### 脚本行为

- 扫描 `.cs`、`.csproj`、`.json`、`.md`、`.ps1` 等常见文本文件扩展名。
- 自动排除 `.git`、`bin`、`obj`、`packages` 等常见生成目录或工具目录。
- 仅重写包含纯 `LF` 换行的文件。

### 参数

| 参数       | 说明               | 默认值   |
| ---------- | ------------------ | -------- |
| `RootPath` | 递归扫描的根目录。 | 当前目录 |

### 示例

```powershell
.\scripts\normalize-crlf.ps1 -RootPath D:\SLB\Prism\PA
```
