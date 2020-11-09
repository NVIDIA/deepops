# DGXIE (on Kubernetes)

DGXie is an all-in-one container for DHCP, DNS, and PXE, specifically tailored to the DGX Base OS.

## Setup

You will need to download the official DGX Base OS ISO image to your provisioning machine. The latest DGX Base OS is available via the NVIDIA Entperprise Support Portal (ESP).

Copy the DGX Base OS ISO to shared storage via a container running in Kubernetes, substituting the path to the DGX ISO you downloaded (be sure to wait for the `iso-loader` POD to be in the *Running* state before attempting to copy the ISO):

```sh
kubectl apply -f workloads/services/k8s/iso-loader.yml
kubectl cp /local/DGXServer-4.0.2.180925_6acd9c.iso $(kubectl get pod -l app=iso-loader -o custom-columns=:metadata.name --no-headers):/data/iso/
```

> Note: If the `iso-loader` POD fails to mount the CephFS volume, you may need to restart the kubelet service on the master node(s): `ansible mgmt -b -a "systemctl restart kubelet"`
> You may see an error that looks like this in your syslog file: `failed to get Plugin from volumeSpec for volume "cephfs" err=no volume plugin matched`

## Configure

Modify the DGXie configuration in `config/helm/dgxie.yml` to set values for the DHCP server and DGX install process.

Modify `config/dhcpd.hosts.conf` to add a static IP lease for each login node and DGX server in the cluster if required. IP addresses should match those used in the `config/inventory` file. You may also add other valid configuration options for dnsmasq to this file.

```sh
grep TODO config/*
```

> Note: There are several `TODO` comments in these configuration files that will likely need to be changed. Depending on the system architecture there may be additional required config changes.

You can get the MAC address of DGX system interfaces via the BMC, for example:

```sh
# interface 1
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x30 0x19 0x00 0x02 | tail -c 18 | tr ' ' ':'
# interface 2
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x30 0x19 0x00 0x12 | tail -c 18 | tr ' ' ':'
```

Modify `config/machines.json` to add a PXE entry for each DGX. Copy the `dgx-example` section and modify the MAC address for each DGX you would like to boot. You can modify boot parameters or install alternate operating systems if required.

Store the config files as config-maps in Kubernetes, even if you have not made any changes (the DGXie container will try to mount these config maps):

```sh
kubectl create configmap dhcpd --from-file=config/dhcpd.hosts.conf
kubectl create configmap pxe-machines --from-file=config/machines.json
```

## Deploy DGXie service

Launch the DGXie service:

```sh
helm install --values config/helm/dgxie.yml workloads/services/k8s/dgxie
```

Check the DGXie logs to make sure the services were started without errors:

```sh
kubectl logs -l app=dgxie
```

> NOTE: If you later make changes to `config/dhcpd.hosts.conf` or `machines.json` you can follow the [steps](#updating-pxe-machines) to update the dgxie service.


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
