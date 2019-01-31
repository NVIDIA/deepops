# ELK

## Deleting the logging stack

```sh
helm del --purge log
helm del --purge elk
kubectl delete statefulset/elk-elasticsearch-data
kubectl delete pvc -l app=elasticsearch
# wait for all statefulsets to be removed before re-installing...
```