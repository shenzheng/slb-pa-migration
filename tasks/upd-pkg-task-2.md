# 任务描述

指定一个工程，将这个工程下所有的包引用，都升级为最新的包，然后执行pipeline，发布该包。

规则如下：

1. 找到所有包引用，含外部公共包。形成dependences
2. 从./doc/package-versions.json以及./doc/shared-package-versions.json，合并出每个包的最新版latest-packages
3. 根据dependences，找到每个包的最新版。编译，执行单元测试
4. 第三步成功后，启动当前分支的pipeline