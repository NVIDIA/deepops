#!/usr/bin/env bash

PATH=/shared/bin:${PATH}

user=${SUDO_USER}

if [ $(id -u) -ne 0 ] ; then
    echo run via sudo
    exit 1
fi

if [ "x${user}" == "x" ] ; then
    echo no user found
    exit 1
fi

tmp_config=$(mktemp)

# 
docker run --rm -ti -v /tmp:/tmp -v /shared:/shared micahhausler/k8s-oidc-helper -c /shared/etc/google_oauth2_client.json --file ${tmp_config} -w

KUBECONFIG=/root/.kube/config /shared/bin/kubectl config --kubeconfig=${tmp_config}  set-cluster deepops --server=https://10..0.1.1:6443 --certificate-authority=/root/.kube/ca.pem --embed-certs=true

chown $(id -u ${user}):$(id -g ${user}) ${tmp_config}
su ${user} -c "cp ~/.kube/config{,.$(date '+%s').bak} 2>/dev/null"
su ${user} -c "KUBECONFIG=~/.kube/config:${tmp_config} /shared/bin/kubectl config view --flatten >> ~/.kube/config"
rm -f ${tmp_config}

# create namespace and role binding for user
KUBECONFIG=/root/.kube/config /shared/bin/kubectl create ns ${user}
KUBECONFIG=/root/.kube/config /shared/bin/kubectl patch namespace ${user} -p '{"metadata":{"annotations":{"scheduler.alpha.kubernetes.io/node-selector":"scheduler=k8s"}}}'
KUBECONFIG=/root/.kube/config /shared/bin/kubectl create rolebinding ${user}-binding --clusterrole=admin --user="${user}@example.com" --namespace=${user}

# set up user config file
su ${user} -c "/shared/bin/kubectl config set-context user --cluster=deepops --namespace=${user} --user=${user}@example.com"
su ${user} -c "/shared/bin/kubectl config use-context user"

echo -e "\n Add /shared/bin to your PATH to use kubectl"
