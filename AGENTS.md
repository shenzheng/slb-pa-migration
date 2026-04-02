# Prism 算法平台改造项目

## 项目概述

这是一个老项目的升级工作，技术栈是以下情况

- 所有的程序都是C#的
- 包管理使用Nuget
- CI/CD使用Azure DevOps

## 老项目概述

- 老项目主要使用.Net Framework
- 使用Windows Service Fabric
- 主要会使用Service Fabric的Actor或Worker模式，如Stateless Worker
- Actor是算法实现的入口。算法的代码在另外的Package当中
  - Actor通常会继承于ComputationActorBase，通过重载方法对外提供
- 底层消息通讯使用RabbitMQ
- 目标部署环境是Virtual Machine Scale Set（Windows Server）

## 新项目概述

- 新项目使用.Net 10
- PlatformTarget为x64
- Actor模式不变，使用Dapr的Actor
- 如果是后台服务，则使用asp.net的服务
- 服务名称需要更换，如原来是Slb.Prism.Rhapsody.Computation.HydraulicsTransientActor，则需要改为Slb.Prism.Rhapsody.Service.HydraulicsTransientActor
- 部署时需要nuspec打包，因为有集成测试等要求
- 部署方式使用Docker方式，最终会部署在AKS上
- 部署需要Helm Chart

## 目录结构

- `../Rhapsody.Computation.DataGenerator/` — 已经改造完的Actor。用途：参考
- `../Rhapsody.Computation.DataGenerator.Master/` — 改造前的Actor。用途：参考
- `../Rhapsody.Service.DrillingKpi/` — 已经改造完的Actor。用途：参考
- `../Rhapsody.Service.DrillingKpi-Master/` — 改造前的Actor。用途：参考
- `../Shared.Library.DrillingKpi` — `Rhapsody.Service.DrillingKpi所依赖 数据结构。用途：参考
- `../Rhapsody.Computation.HydraulicsTransient/` — 待改造的的Actor以及Stateless Work
- `../Rhapsody.Computation.HydraulicsTransient-master/` — 改造前的Actor。用途：参考
- `../Rhapsody.Library.ComputationDaprAdapter/` - Actor依赖的底层包。用途：参考
- `../Core.Service.FileExportManager/` - Stateless Work的样例。用途：参考
- `../Pipeline/rcis-devops-template` - Pipeline底层包。用途：参考

## 代码要求

- 所有文本文件的换行必须符合Windows的CR/LF要求。
- 每个C#工程，尽量使用GlobalUsings.cs，减少每个C#文件中的using。
- appsettings.json需要配置logging，其中ProviderName需要根据服务名修改。

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information"
    }
  },
  "LoggerSetup": {
    "LogLevelConfiguration": {
      "DefaultLevel": "Trace",
      "NamespaceLevels": {
        "Microsoft": "Warning",
        "System": "Error"
      }
    },
    "SinkConfiguration": {
      "Sinks": [
        {
          "Name": "Console",
          "Args": {
            "TextFormatter": "Serilog.Formatting.Elasticsearch.ElasticsearchJsonFormatter, Serilog.Formatting.Elasticsearch"
          }
        }
      ]
    },
    "EnricherConfiguration": {
      "Properties": {
        "ProviderName": "Slb.Prism.Rhapsody.Service.DrillingKpi-3"
      }
    }
  },
  "AllowedHosts": "*"
}
```

## 文档要求

- 格式均为Markdown文档
- Markdown文档需要符合markdownlint要求