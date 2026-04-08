# 任务描述

输入的内容不变，目标Repository的目录以及ProviderName，其中ProviderName的尾号是版本。

参考upgrade-plan.md以及所有相关代码和文档，优化upgrade-plan.md，生成upgrade-plan-2.0.md。

## 优化要求

- 增加一个步骤，在目标Repositiry创建dapr分支（来自当前的master），且未来在此分支上做事
- 将迁移变为一个个步骤
- 每个步骤设置检查条件
- 从当前上下文提取出Repository名称，目录信息，版本号等上下文参数
- 每个步骤所需要修改的文件，需要提供参考文件
  - 例如：
    - Project文件
    - Dockerfile
    - nuspec
    - pipeline.json
    - appsetting.json
    - azure-pipelines-ci.yml
  - 这些参考文件中，如果需要上下文参数，则需要由占位符占位
- 每个步骤需要给出验证逻辑，验证通过后单独签入
- 最终还需要通过统一的核对环节进行验证，需要给出最终验证逻辑
