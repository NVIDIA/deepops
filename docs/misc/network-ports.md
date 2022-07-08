# Network Ports

Requirements for open network ports

- [Network Ports](#network-ports)
  - [Kubernetes deployments](#kubernetes-deployments)
  - [Slurm deployments](#slurm-deployments)

DeepOps can be used to deploy a wide variety of network services, many of which are highly customizable, or which can be enabled or disabled for any given cluster deployment.
Additionally, for performance reasons, we typically test DeepOps in an environment where no host-based firewall restricts traffic _between_ cluster nodes.
(Though a firewall may be used to manage external access to the cluster.)

Because of this, we don't currently maintain a comprehensive list of network ports used by the software that DeepOps deploys.
The best way to obtain a comprehensive list of open ports is to deploy first in a test environment
(e.g., using the [virtual cluster functionality](../../virtual)),
and check what ports are required for the particular set of software you wise to deploy.

This page documents a subset of commonly required ports, either by linking to documentation for the software components (e.g., Slurm and Kubernetes),
listing known ports for major services such as NFS,
or listing known ports that we configure within DeepOps itself.

## Kubernetes deployments

- [Kubernetes Ports and Protocols](https://kubernetes.io/docs/reference/ports-and-protocols/)
- SSH (all hosts): 22/tcp
- NFS:
  - All hosts: 111/tcp, 111/udp
  - NFS server: 2049/tcp, 2049/udp
  - [NFS firewall guide](https://tldp.org/HOWTO/NFS-HOWTO/security.html#FIREWALLS)
- rsyslog server: 514/tcp
- Caching container registry: 5000/tcp
- Internal cluster container registry: 31500/tcp
- Monitoring
  - Prometheus web interface: 30500/tcp (Kubernetes NodePort)
  - Grafana web interface: 30200/tcp (Kubernetes NodePort)
  - AlertManager web interface: 30400/tcp (Kubernetes NodePort)
  - Prometheus node exporter: 9100/tcp
  - DCGM node exporter: 9400/tcp

## Slurm deployments

- [Slurm Network Configuration Guide](https://slurm.schedmd.com/network.html)
- SSH (all hosts): 22/tcp
- NFS:
  - All hosts: 111/tcp, 111/udp
  - NFS server: 2049/tcp, 2049/udp
  - [NFS firewall guide](https://tldp.org/HOWTO/NFS-HOWTO/security.html#FIREWALLS)
- rsyslog server: 514/tcp
- Caching container registry: 5000/tcp
- Monitoring stack:
  - Prometheus web interface: 9090/tcp
  - Grafana web interface: 3000/tcp
  - Prometheus node exporter: 9100/tcp
  - DCGM node exporter: 9400/tcp
- Open OnDemand: 9050/tcp
