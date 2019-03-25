Load Balancer and Ingress
===

Kubernetes provides a variety of mechanisms to expose pods in your cluster to external networks.
Two key concepts for routing traffic to your services are:

* [Load Balancers](https://kubernetes.io/docs/concepts/services-networking/#loadbalancer), which expose an external IP and route traffic to one or more pods inside the cluster.
* [Ingress controllers](https://kubernetes.io/docs/concepts/services-networking/ingress/), which provide a mapping between external HTTP routes and internal services.
    Ingress controllers are typically exposed using a Load Balancer external IP.

DeepOps provides a script you can run to configure a simple Load Balancer + Ingress setup:

```
./scripts/k8s_deploy_ingress_metallb.sh
```

This script will set up a software-based L2 Load Balancer using [MetalLb](https://metallb.universe.tf/), as well as a basic Ingress controller based on [NGINX](https://github.com/kubernetes/ingress-nginx).

----------------------

The different examples and optional services included with DeepOps may use different mechanisms to provide external access.
Depending on the config, each may:

* Use an Ingress to get an HTTP route on the shared NGINX IP.
* Use the Load Balancer directly and get their own external IP.
* Use a [NodePort](https://kubernetes.io/docs/concepts/services-networking/#nodeport) config to expose themselves via a local port on the actual nodes.

For more detail on Kubernetes networking, and the different ways that services can be accessed, see the [official documentation on service networking concepts](https://kubernetes.io/docs/concepts/services-networking/).
