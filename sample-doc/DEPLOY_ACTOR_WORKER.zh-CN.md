# HydraulicsTransient CI/CD 部署约定说明

## 背景

该服务使用 `InternalImageDotNetCloud` 流水线模板，并通过共享的 CD 包 `Slb.Prism.CD.Pipeline` 完成部署。

这类服务能否稳定部署，不只取决于业务代码本身，还依赖一组平台默认但未完全显式写出的约定，包括：

- NuGet 包内 Helm Chart 的目录结构
- 镜像命名方式
- Dockerfile 命名方式
- 应用运行端口与 Dapr 端口
- Helm values 的覆盖链路

如果这些约定没有对齐，部署可能表现为：

- 没有使用预期的 Helm Chart
- Dapr annotation 丢失
- 镜像拉取失败
- Pod 一直无法 Ready
- Helm 在真正部署前就失败

## 关键经验

### 1. NuGet 包内 `deploy/` 目录必须保留

可部署的 Helm Chart 应保存在 NuGet 包的 `deploy/` 目录下。

推荐的 `nuspec` 约定：

```xml
<files>
  <file src="deploy\**\*.*" target="deploy" />
  <file src="SharedAssemblyInfo.cs" target="" />
  <file src="CustomizeValues.ps1" target="" />
</files>
```

如果把 Chart 打平到包根目录，或者包结构不符合 CD 预期，CD 可能会回退到其他 Chart 路径，甚至使用运行时生成的模板，从而导致：

- Dapr annotation 缺失
- 镜像名与实际构建结果不一致
- 使用旧模板行为而不是服务自定义模板

本地手工验证nuget包的正确性

```powershell
nuget.exe pack .\Slb.Prism.Rhapsody.Service.HydraulicsTransient.nuspec -Version 9.9.9-local-test -OutputDirectory .\_pkg_test
```

使用zip工具解压缩.nupkg，验证是否是以下结构：

```pre
├─ CustomizeValues.ps1
├─ SharedAssemblyInfo.cs
└─ deploy
   ├─ Chart.yaml
   ├─ values.yaml
   ├─ templates
   │  └─ deployment.yaml
   └─ charts
      └─ worker
```

> 如果Chart.yaml没有在deploy目录下，CD流程会使用会使用一个默认的helm chart。可以从日志中是否从deployTemplate目录下获取helm来判定。

### 2. 镜像命名遵循平台隐含约定

Image 阶段实际推送的镜像是：

- `drillops.azurecr.io/rhapsody/hydraulicstransient-webapi:<tag>`
- `drillops.azurecr.io/rhapsody/hydraulicstransient-worker:<tag>`

但 CD 注入到 values 中的基础 repository 往往是：

- `drillops.azurecr.io/rhapsody/hydraulicstransient`

这意味着 Helm Chart 模板必须自己补上组件后缀：

- webapi 镜像：

```yaml
containers:
  - name: actor
    image: "{{ .Values.image.repository }}-webapi:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

- worker 镜像：

```yaml
containers:
  - name: worker
    image: "{{ .Values.image.repository }}-worker:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

如果没有补 `-webapi` / `-worker`，部署会直接报：

- `ImagePullBackOff`
- `ErrImagePull`

### 3. Dockerfile 命名也是契约的一部分

当前流水线默认识别：

- `Dockerfile-webapi`
- `Dockerfile-worker`

如果文件名偏离这个模式，镜像可能无法被正确构建或推送。

### 4. 端口必须全链路一致

以下配置必须保持一致：

- 应用运行时实际监听端口
- Dockerfile 中的 `EXPOSE`
- Helm Chart 中的 `containerPort`
- Dapr annotation 中的 `dapr.io/app-port`
- 显式传入的 ASP.NET 环境变量

本次 `HydraulicsTransient` 典型问题是：

- actor 应用实际监听 `8080`
- Dapr sidecar 却一直等待 `80`

结果就是：

- actor 容器已经启动
- daprd 一直无法探测成功
- Pod 长时间无法 Ready

当前稳定做法是统一到 `8080`。

### 5. Dapr 是否启用同时受模板逻辑和最终 values 影响

主服务应开启 Dapr，worker 默认不启用 Dapr。

模板判断建议写成：

```yaml
{{- if (default true .Values.enableDapr) }}
```

如果写成过于严格的：

```yaml
{{- if eq true .Values.enableDapr }}
```

当 CD 在 values 覆盖过程中丢掉 `enableDapr` 时，annotation 会被静默跳过，最终表现为没有 Dapr sidecar。

### 6. YAML 合法性在 Helm 执行前就会被检查

`deploy/values.yaml` 语法错误时，部署可能在 `helm upgrade --install` 之前就失败。

实际遇到过的问题包括：

- 缩进错误
- 重复 key

这些错误会先在 CD 使用的 PowerShell YAML 解析阶段暴露出来。

### 7. Deployment selector 不能随意改变

如果新版本 Deployment 的 selector 与已部署版本不一致，Helm upgrade 可能失败，例如：

```text
spec.selector: field is immutable
```

因此：

- `matchLabels`
- `template.metadata.labels`

这些与 selector 相关的字段必须保持向后兼容。

## Values 覆盖链路

Helm 最终生效的 values 通常来自多层输入。

按优先级从低到高：

### 1. 包内默认 values

- `deploy/values.yaml`

负责定义服务自身默认配置，例如：

- 默认端口
- Dapr 开关
- worker 默认配置
- probes
- 默认环境变量

### 2. 运行时计算 values

- `values-1-calculated.yaml`

由 CD 根据环境和服务元数据生成，通常会覆盖：

- `image`
- `worker.image`
- `environmentVariables`
- `worker.environmentVariables`
- `replicaCount`
- `worker.replicaCount`
- `affinity`
- `worker.affinity`
- `ingress.enabled`
- `worker.ingress.enabled`

需要特别注意：

`environmentVariables` 往往是整段替换，而不是逐项 merge。

这意味着你在 `deploy/values.yaml` 中写的默认环境变量，可能会被整段覆盖掉。

### 3. 部署参数 values

- `values-2-deployargs.yaml`

通常来自 EnvPatch 或 deploy args，主要覆盖：

- `resources`
- `worker.resources`

也就是 CPU / Memory 的 requests 和 limits。

### 4. Helm 命令行 `--set`

优先级最高，常见示例：

- `--set envType=dev`
- `--set worker.envType=dev`

## 哪些文件或参数会影响最终 values

### 服务仓库内

- `deploy/values.yaml`
- `deploy/templates/*.yaml`
- `deploy/charts/worker/**`
- `CustomizeValues.ps1`
- `pipeline.json`
- `azure-pipelines-ci.yml`
- `*.nuspec`

### 服务仓库外

- `rcis-devops-template` 中的共享流水线模板
- `Slb.Prism.CD.Pipeline`
- CD 环境配置 / EnvPatch / deployTemplateArgs
- 共享 Image 流水线中的镜像命名规则

## 各部分职责

### `deploy/values.yaml`

定义服务自有默认值：

- 端口
- Dapr 是否开启
- 默认环境变量
- worker 默认参数
- probes
- Service 形态

### `values-1-calculated.yaml`

定义环境解析后的运行时值：

- 镜像 repository
- 镜像 tag
- 环境变量，例如 `env`、`consulUri`
- 副本数
- affinity
- ingress 开关

### `values-2-deployargs.yaml`

定义部署资源参数：

- CPU requests / limits
- Memory requests / limits

### `CustomizeValues.ps1`

服务级最后一层自定义扩展点。

即使暂时没有特殊逻辑，也建议保留空脚本，以兼容 CD 平台预期。

## 推荐验证清单

在合并或提升环境前，建议至少检查以下内容：

1. 确认生成的 NuGet 包包含：

- `deploy/Chart.yaml`
- `deploy/values.yaml`
- `deploy/templates/...`
- `CustomizeValues.ps1`

2. 确认 Deploy 日志中的 Helm 实际使用：

```text
<package>/deploy
```

而不是意外切到其他 fallback Chart。

3. 确认渲染后的镜像名与实际推送的镜像一致：

- `*-webapi`
- `*-worker`

4. 确认应用实际监听端口与以下内容一致：

- Dockerfile `EXPOSE`
- Chart `containerPort`
- Dapr `app-port`
- ASP.NET 环境变量

5. 确认最终 values 中仍然保留关键字段，例如：

- `enableDapr`
- 预期的 `containerPort`

6. 推送前检查 `deploy/values.yaml` 语法是否合法。

7. 对已有 release，避免修改 Deployment selector。

## 实际落地结论

对本服务来说，最重要的部署契约可以概括为：

- Helm Chart 必须打进 NuGet 包的 `deploy/` 目录
- 建议始终保留 `CustomizeValues.ps1`
- 镜像命名必须与 `-webapi` / `-worker` 约定一致
- 应用运行端口与 Dapr 端口必须一致
- 要意识到 CD 会整体覆盖某些 values 段，尤其是 `environmentVariables`
- Chart 的 labels / selectors 需要按“可升级”方式维护

# 附录

## 参考文档

[Customized helm template for sf k8s migration (webapi + statefulset + worker)](https://dev.azure.com/slb1-swt/Prism/_wiki/wikis/Prism.wiki/38428/Customized-helm-template-for-sf-k8s-migration-(webapi-statefulset-worker))

## EnvPath

[EnvPatch source sample](https://dev.azure.com/slb1-swt/Prism/_git/CDaaS.Ext?path=/EnvPatch/coint/core/Slb.Prism.Core.Service.StreamGrid-1.json)

```json
{

  "deployTemplateArgs": {

    "replicaCount": 1,

    "resources": { "limits": {"cpu":"500m","memory":"512Mi"}, "requests": {"cpu":"250m","memory":"256Mi"} },

    "statefulset": {

      "replicaCount": 10,

      "resources": { "limits": {"cpu":"500m","memory":"512Mi"}, "requests": {"cpu":"250m","memory":"256Mi"} }

    },

    "worker": {

      "replicaCount": 1,

      "resources": { "limits": {"cpu":"250m","memory":"512Mi"}, "requests": {"cpu":"250m","memory":"256Mi"} }

    }

  },

  "docApiPath": "/swagger/docs/v1/swagger.json",

  "type": "Kubernetes Service",

  "targetServer": "[Slb.Prism.AKS]",

  "updateInternalUri": true

}
```
