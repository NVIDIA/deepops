Using Proxy with DeepOps (k8s Cluster Install)
======================

Not all environments can freely download and install software for security reasons which is no surprise. However, setting up a proxy for all tasks may not be the best option for all environments. The ansible playbooks and deepops scripts were modified to leverage a proxy if its available but only during setup/provisoning. Its important not only the `HTTP_PROXY` and `HTTPS_PROXY` be configured to gain access to packages, software, and k8s config files, but `NO_PROXY` be also set. Hosts listed in the the `NO_PROXY` varaible are *not* used when a HTTP request is made. Why this is important is because services and commands like `kubectl` use the HTTP protocol to access k8s services. Its out of scope to list those services here, best to refer to k8s documentation.

Proxy format: http://user:password@proxyIP:Proxy:Port/


Playbook k8s-cluster.yml
----------

To prepare using proxies for the installation of DeepOps via the k8s-cluster.yml playbook, there are 2 additional seteps required. After downloading deepops via git, edit the script `proxy.sh` before executing step `#2 Set up your provisoning machine`. Then after the Kubernetes cluster is up and running use the proxies to complete the additional found in `Using Kubernetes`. Below are the details. 

### Edit proxy.sh
Manually edit the file and provide the necessary values for all 3 varaibles - HTTPS_PROXY, HTTP_PROXY, NO_PROXY. The NO_PROXY variable should have a comma separated list of hostnames, IP addresses, domain names, or a mixture of both. Asterisks can be used as wildcards.

```
# Example Proxy details
export http_proxy="http://10.0.2.5:3128"
export https_proxy="http://10.0.2.5:3128"
export no_proxy="localhost,cluster.local,127.0.0.1,::1,10.0.2.10,10.0.2.20,10.0.2.30" 
```

The presence of values in the config file directs the `scripts/setup.sh` script to use its environment variables to download/install software. It will also update the `config/group_vars/all.yml` so that the ansible playbooks will also use proxies. 

_Its important to note that docker will also be configued to use the proxy to download containers._

### Using Kubernetes

Before executing the scripts to continue setting up and installing services you can:

1. Run the `scripts/deepops/proxy.sh` script to setup environment variables. Then continue running all the scripts necessary for your environment. 

2. Rather than setup the variables for your current shell, you can run each script to use the proxy without impacting your current env. For example:
`. scripts/deepops/proxy.sh && scripts/k8s/deploy_rook.sh`
