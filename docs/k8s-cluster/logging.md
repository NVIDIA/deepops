# Logging

Centralized logging is provided by Filebeat, Elasticsearch and Kibana.

- [Logging](#logging)
  - [Installation](#installation)
    - [Install and validate the Elasticsearch cluster](#install-and-validate-the-elasticsearch-cluster)
    - [Install Filebeat](#install-filebeat)
    - [Install Kibana](#install-kibana)
  - [Deleting the logging stack](#deleting-the-logging-stack)

## Installation

The following procedure walks through installation of a centralized logging stack using the Helm repositories provided by [Elastic NV](https://www.elastic.co/).

Our centralized logging solution requires that all hosts be configured with the same timezone and synchronized clocks.
This should be done automatically in our Kubernetes deployment process, but can be enforced manually by running the Chrony playbook:

```bash
ansible-playbook playbooks/generic/chrony-client.yml
```

Add the Elastic repo in Helm:

```bash
helm repo add elastic https://helm.elastic.co
```

### [Install and validate the Elasticsearch cluster](https://github.com/elastic/helm-charts/blob/main/elasticsearch/README.md)

```bash
# Install Elasticsearch
# - Note that this document uses three replicas for availability, but you may
#   want to set a different value depending on cluster size
helm install elasticsearch elastic/elasticsearch --set replicas=3

# Wait for the cluster to come online
kubectl get pods --namespace=default -l app=elasticsearch-master -w

# Test the cluster health
helm --namespace=default test elasticsearch
```

### [Install Filebeat](https://github.com/elastic/helm-charts/blob/main/filebeat/README.md)

Note that the default Filebeat configuration will import all container logs from the Kubernetes cluster nodes.

```bash
# Install Filebeat
helm install filebeat elastic/filebeat

# Wait for all containers to come up
kubectl get pods --namespace=default -l app=filebeat-filebeat -w
```

### [Install Kibana](https://github.com/elastic/helm-charts/blob/main/kibana/README.md)

```bash
# Install Kibana
helm install kibana elastic/kibana

# Wait for the container to come up
kubectl get pods --namespace=default -l app=kibana -w
```

By default, Kibana is only deployed as a ClusterIP service.
In order to expose it for user access, see the [chart documentation](https://github.com/elastic/helm-charts/blob/main/kibana/README.md)
or just expose it as a NodePort service:

```bash
kubectl expose deployment kibana-kibana \
    --type=NodePort \
    --name=kibana-nodeport

service/kibana-nodeport exposed

kubectl get service kibana-nodeport
NAME              TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kibana-nodeport   NodePort   10.233.39.104   <none>        5601:30965/TCP   42s
```

## Deleting the logging stack

If there is an issue, you can follow these steps to delete the logging stack:

```bash
helm delete kibana
helm delete filebeat
helm delete elasticsearch
kubectl delete pvc -l app=elasticsearch-master
```
