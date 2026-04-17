# 任务描述

生成一个skill，查询得到所有Shared packages的最新版本。

举例：

```text
请更新Shared packages的最新版本

|Package | Version
|--|--|
|Slb.Prism.Rhapsody.Library.ComputationDaprAdapter|0.1.0.15636617|
...
```

并且生成在./doc/shared-package-versions.json

为了完成这个skill，可以补充脚本。

这个信息需要去查询ADO的artifacts。