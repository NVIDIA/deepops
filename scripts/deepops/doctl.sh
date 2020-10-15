#!/usr/bin/env bash


nodes=$(scontrol show node "${1}" | grep -oe "^NodeName=[a-Z,0-9,-]*" | cut -d= -f2)

shift

#echo ${nodes}

case "$1" in
    k8s)
        for node in ${nodes} ; do 
            echo "${node}: "
            sudo scontrol update node=${node} state=drain reason=k8s >/dev/null
            kubectl uncordon ${node} >/dev/null
            kubectl label --overwrite node ${node} scheduler=k8s >/dev/null
            echo -n "k8s: "
            kubectl get node ${node} | tail -1 | awk '{print $2}'
            echo -n "slurm: "
            scontrol show node ${node} | grep -oe "State=[a-Z,+]*" | cut -d= -f2
        done
        ;;
    slurm)
        for node in ${nodes} ; do 
            echo "${node}: "
            kubectl cordon ${node} >/dev/null
            sudo scontrol update node=${node} state=idle reason=slurm >/dev/null
            kubectl label --overwrite node ${node} scheduler=slurm >/dev/null
            echo -n "k8s: "
            kubectl get node ${node} | tail -1 | awk '{print $2}'
            echo -n "slurm: "
            scontrol show node ${node} | grep -oe "State=[a-Z,+]*" | cut -d= -f2
        done
        ;;
    state)
        for node in ${nodes} ; do 
            echo -n "${node}: "
            kubectl get node ${node} -o yaml | grep scheduler: | awk '{print $2}'
        done
        ;;
    *)
        echo "Usage: $0 [node] [k8s|slurm|state]"
        ;;
esac
