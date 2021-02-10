Centralized logging with syslog
===============================

Both the Slurm and Kubernetes cluster playbooks include a minimal implementation of centralized cluster logging using rsyslog.

Rsyslog was selected for the minimal cluster logging implementation in order to provide a light-weight solution using software already installed on the nodes.
This ensures that logs are recorded in one place, making it easier to debug node-specific issues even in the case where the nodes are down or non-responsive.
However, for a more full-featured logging solution with search and visualization capabilities, we recommend deploying the [ELK stack](../k8s-cluster/logging.md) or other log solution.

In the syslog-based implementation, the first cluster management node is selected as a syslog server and listens on `rsyslog_client_tcp_port` for connections.
The remaining nodes in the cluster then forward their logs to the selected syslog server.
Log files for remote nodes are stored on the syslog server in node-specific files under `/var/log/hosts`.

On Slurm clusters, the Slurm daemon logs are ingested by rsyslog and forwarded to the syslog server.
On Kubernetes clusters, the kubelet logs are currently included in syslog, but pod logs are not imported by default.
