# 任务描述

整理所有工程和nuget包名称的对应关系。

我们需要收集每个Repository下的nuspec文件，然后找出它们对应的包名称和版本。

在scripts目录下生成一个脚本，可以生成repository和nuget包名称和版本的markdown文档。

可以为该脚本指定根目录，这样会扫描每一个一级项目工程目录，找到nuspec文件，找到对应的nuget包和版本号。然后输出markdown到指定的文件名。

将该脚本的说明补充道./doc/scritps.md中。
