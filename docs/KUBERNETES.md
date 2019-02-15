Kubernetes
===

## Kubespray

More information on Kubespray can be found in the official [Getting Started Guide](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md)

## Using Kubernetes

__Test that GPU support is working:__

```sh
kubectl apply -f tests/gpu-test-job.yml
kubectl exec -ti gpu-pod -- nvidia-smi -L
kubectl delete pod gpu-pod
```

## Helm

Helm is a Kubernetes package manager

__Install the Helm client__

```sh
# Installs the helm binary in /usr/local/bin
./scripts/install_helm.sh
```

## Monitoring

Cluster monitoring is provided by Prometheus and Grafana

__Deploy the monitoring and alerting stack:__

Be sure the Helm client is installed

```sh
helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/
helm install coreos/prometheus-operator --name prometheus-operator --namespace monitoring --values config/prometheus-operator.yml
kubectl create configmap kube-prometheus-grafana-gpu --from-file=config/gpu-dashboard.json -n monitoring
helm install coreos/kube-prometheus --name kube-prometheus --namespace monitoring --values config/kube-prometheus.yml
```

To collect GPU metrics, label each GPU node and deploy the DCGM Prometheus exporter:

```sh
kubectl label nodes <gpu-node-name> hardware-type=NVIDIAGPU
kubectl create -f services/dcgm-exporter.yml
```

Service addresses:

* Grafana: http://mgmt:30200
* Prometheus: http://mgmt:30500
* Alertmanager: http://mgmt:30400

> Where `mgmt` represents a DNS name or IP address of one of the management hosts in the kubernetes cluster.
The default login for Grafana is `admin` for the username and password.

## Kubernetes Dashboard

You can access the Kubernetes Dashboard at the URL:

https://first_master:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login

For more information, see:

  * [Kubespray Getting Started Guide](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md#accessing-kubernetes-dashboard)
  * [Kubernetes Dashboard Documentation](https://github.com/kubernetes/dashboard)
