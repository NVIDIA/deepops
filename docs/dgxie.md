# DGXIE

## Updating DHCP Configuration

If you make changes to `config/dhcpd.hosts.conf`, you can update the file in Kubernetes and restart the service with:

```sh
kubectl create configmap dhcpd --from-file=config/dhcpd.hosts.conf -o yaml --dry-run | kubectl replace -f -
kubectl delete pod -l app=dgxie
```

## Updating PXE Machines

If you make changes to `machines.json`, you can update the file without having to restart the DGXie POD:

```sh
kubectl create configmap pxe-machines --from-file=config/machines.json -o yaml --dry-run | kubectl replace -f -
```