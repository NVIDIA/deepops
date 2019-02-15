# Helm

Some services are installed using [Helm](https://helm.sh/), a package manager for Kubernetes.

## Manual Install

Install the Helm client by following the instructions for the OS on your provisioning system: https://docs.helm.sh/using_helm/#installing-helm

If you're using Linux, the script `scripts/install_helm.sh` will set up Helm for the current user.

Be sure to install a version of Helm matching the version in `config/kube.yml`.

If `helm_enabled` is `true` in `config/kube.yml`, the Helm server will already be deployed in Kubernetes.

If the the value of `helm_enabled` was set to `false` in the `config/kube.yml` file helm will need to manually be installed. This is also how helm should be reinstalled.

```sh
kubectl create sa tiller --namespace kube-system
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --node-selectors node-role.kubernetes.io/master=true
```
