# 任务描述

编写一个脚本。扫描Actors和Shared下的每一个工程，收集其所依赖Package的版本信息。
该脚本在doc下生成文档，文档分为两个部分（章节划分）。
此脚本用法更新在README.md中。

## 第一部分

按照字母顺序+版本号排序，为package生成一个排序的表格。主要是三列：

- Pacakge Name
- Version
- Source（如来自于Actors以及Shared的工程，则列出Repository名称）

## 第二部分

生成每个Package以及每个版本，被引用的包或工程。每个Package为一节。
