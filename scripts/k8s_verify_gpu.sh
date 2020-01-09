#!/usr/bin/env bash
# This script is meant to be run after a clean K8S deployment (it can also be run later for debugging)
# It will get a count of all the GPU in the cluster and attempt to run a job against each one
# Check the output and verify the number of nodes and GPUs is as expected
# TODO: This script should be wrapped by Ansible to verify that the output of nvidia-smi on each node matches K8S

export KFCTL=${KFCTL:-~/kfctl}
export CLUSTER_VERIFY_NS=${CLUSTER_VERIFY_NS:-cluster-gpu-verify}
export CLUSTER_VERIFY_EXPECTED_PODS=${CLUSTER_VERIFY_EXPECTED_PODS:-}

# Ensure we start in the correct working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
cd "${ROOT_DIR}" || exit 1
TESTS_DIR=$ROOT_DIR/tests

job_name=$(cat $TESTS_DIR/cluster-gpu-test-job.yml | grep -A1 metadata | awk '{print $2}')
echo "job_name=$job_name"

# Count the number of nodes with GPUs present and the total GPUs across all nodes
number_gpu_nodes=0
total_gpus=0
gpus=`kubectl describe nodes | grep -A7 Capacity | grep nvidia.com/gpu | awk '{print $2}'`
for node in ${gpus}; do
    echo "Node found with ${node} GPUs"
    let number_gpu_nodes=$number_gpu_nodes+1
    let total_gpus=$total_gpus+$node
done
echo "total_gpus=$total_gpus"

echo "Creating/Deleting sandbox Namespace"
kubectl delete ns ${CLUSTER_VERIFY_NS}
kubectl create ns ${CLUSTER_VERIFY_NS}

echo "updating test yml"
sed -i "s/.*DYNAMIC_PARALLELISM.*/  parallelism: ${total_gpus} # DYNAMIC_PARALLELISM/g" $TESTS_DIR/cluster-gpu-test-job.yml
sed -i "s/.*DYNAMIC_COMPLETIONS.*/  completions: ${total_gpus} # DYNAMIC_COMPLETIONS/g" $TESTS_DIR/cluster-gpu-test-job.yml

echo "executing ..."
kubectl -n ${CLUSTER_VERIFY_NS} create -f $TESTS_DIR/cluster-gpu-test-job.yml > /dev/null
sleep 10

# The test job sleeps for 30 seconds, so if we create the pods and wait less than 30 seconds we should have everything in either a RUNNING or PENDING state
pods_output=$(kubectl -n ${CLUSTER_VERIFY_NS} get pods | grep ${job_name} | awk '$3 ~/Running/ {print $1}' )
string_array=($pods_output)
number_pods=${#string_array[@]}

# loop through all pod from each node
i=1
while [ $i -le $total_gpus ]; do
    kubectl -n ${CLUSTER_VERIFY_NS} logs -f ${string_array[$k]}
    let i=i+1
done

echo "Number of Nodes: ${number_gpu_nodes}"
echo "Number of GPUs: ${total_gpus}"
echo "${number_pods} / ${total_gpus} GPU Jobs COMPLETED"

if [ $number_pods -lt $total_gpus ]; then
    echo "ERROR: Detected ${total_gpus} GPUs, but found ${number_pods} Successful Pods"
    echo "GPU driver test failed, use 'kubectl -n ${CLUSTER_VERIFY_NS} describe nodes' to check GPU driver status"
    exit 1
elif [ -n "${CLUSTER_VERIFY_EXPECTED_PODS}" ]; then
    if [ "${CLUSTER_VERIFY_EXPECTED_PODS}" != "${number_pods}" ]; then
        echo "ERROR: expected ${CLUSTER_VERIFY_EXPECTED_PODS} Pods, found ${number_pods}"
        echo "GPU driver test failed, use 'kubectl -n ${CLUSTER_VERIFY_NS} describe nodes' to check GPU driver status"
        exit 1
    fi
fi

# Only delete on success to allow debugging
kubectl delete ns ${CLUSTER_VERIFY_NS}
