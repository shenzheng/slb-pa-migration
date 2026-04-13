# 常用命令

## 查看K8S中dapr版本

```
kubectl get pods -n dapr-system -o jsonpath="{.items[*].spec.containers[*].image}"
```