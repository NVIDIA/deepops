Ingress
===

## On-Prem LoadBalancer

[MetalLB](https://metallb.universe.tf/) is a load-balancer implementation for bare metal Kubernetes clusters, using standard routing protocols.

```sh
# Modify IP range
vi config/helm/metallb.yml

# Deploy
helm install --name metallb --values config/helm/metallb.yml stable/metallb
```

> For more configuration options, see: https://metallb.universe.tf/configuration/
