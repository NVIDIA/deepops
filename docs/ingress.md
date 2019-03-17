Ingress
===

An ingress controller routes external traffic to services.

## Nginx

Modify `config/helm/ingress.yml` if needed and install the nginx ingress controller:

```sh
helm install --values config/helm/ingress.yml stable/nginx-ingress
```

You can check the ingress controller logs with:

```sh
kubectl logs -l app=nginx-ingress
```

## MetalLB

[MetalLB](https://metallb.universe.tf/) is a load-balancer implementation for bare metal Kubernetes clusters, using standard routing protocols.

```sh
# Modify IP range
vi config/helm/metallb.yml

# Deploy
helm install --name metallb --values config/helm/metallb.yml stable/metallb
```

> For more configuration options, see: https://metallb.universe.tf/configuration/
