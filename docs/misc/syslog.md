Centralized logging with syslog
===============================

Both the Slurm and Kubernetes cluster playbooks include a minimal implementation of centralized cluster logging using rsyslog.

Rsyslog was selected for the minimal cluster logging implementation in order to provide a light-weight solution using software already installed on the nodes.
This ensures that logs are recorded in one place, making it easier to debug node-specific issues even in the case where the nodes are down or non-responsive.
However, for a more full-featured logging solution with search and visualization capabilities, we recommend deploying the [ELK stack](../k8s-cluster/logging.md) or other log solution.

In the syslog-based implementation, the first cluster management node is selected as a syslog server and listens on `rsyslog_client_tcp_port` for connections.
The remaining nodes in the cluster then forward their logs to the selected syslog server.
Log files for remote nodes are stored on the syslog server in node-specific files under `/var/log/deepops-hosts`.

On Slurm clusters, the Slurm daemon logs are additionally ingested by rsyslog and forwarded to the syslog server.
On Kubernetes clusters, the Kubelet logs are already included in the syslog feed.


## Using an external syslog server

If your site already includes a syslog server, you can forward your logs there using the following variables:

* On Slurm: set `slurm_enable_rsyslog_server: false` and `slurm_enable_rsyslog_client: true`
* On Kubernetes: set `kube_enable_rsyslog_server: false` and `slurm_enable_rsyslog_client: true`
* Set `rsyslog_client_tcp_host` to the hostname or IP address of your syslog server
* Set `rsyslog_client_tcp_port` to the port your syslog server listens on for TCP logs
