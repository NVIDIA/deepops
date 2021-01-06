# ELK

Centralized logging is provided by Filebeat, Elasticsearch and Kibana.

## Installation

> Note: The ELK Helm chart is current out of date and does not provide support for setting the Kibana NodePort

*todo:*
  * filebeat syslog module needs to be in UTC somehow, syslog in UTC?
  * fix kibana nodeport issue

Make sure all systems are set to the same timezone:

```sh
ansible all -k -b -a 'timedatectl status'
```

To update, use: `ansible <hostname> -k -b -a 'timedatectl set-timezone <timezone>'

Install [Osquery](https://osquery.io/):

```sh
ansible-playbook -k ansible/playbooks/osquery.yml
```

Deploy Elasticsearch and Kibana:

```sh
helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
helm install --name elk --namespace logging --values config/helm/elk.yml incubator/elastic-stack
```

> Important: The ELK stack will take several minutes to install,
wait for elasticsearch to be ready in Kibana before proceeding.

Verify that all of the ELK services are `RUNNING` with:

```sh
kubectl get pods -n logging
```

Launch Filebeat, which will create an Elasticsearch index automatically:

```sh
helm install --name log --namespace logging --values config/helm/filebeat.yml stable/filebeat
```

Kibana can now be reached at http://\<kube-master\>:30700

## Deleting the logging stack

If there is an issue, you can follow these steps to delete the logging stack:

```sh
helm del --purge log
helm del --purge elk
kubectl delete statefulset/elk-elasticsearch-data
kubectl delete pvc -l app=elasticsearch
# wait for all statefulsets to be removed before re-installing...
```
