#!/usr/bin/env bash
# This script is meant to be run after a clean K8S deployment on a DGX device but 
# have also been run on an single rtx 3090, with some manipulation. These
# deployments may be accessed via nodeport binding via a Jupyter Notebook. Notebooks 
# include State-of-the-Art Deep Learning # examples that are easy to train and deploy, 
# achieving the best reproducible accuracy and performance with NVIDIA CUDA-X 
# software stack running on NVIDIA Volta, Turing and Ampere GPUs. Data download scripts
# are included in all containers but will not be build "as-is". many are > 15Gb once
# downloaded.

export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1
export DLE_DEPLOYMENT=0

DEEP_LEARNING_DIR="${DEEP_LEARNING_DIR:-workloads/examples/k8s/deep-learning-examples/}"
DEEP_LEARNING_COMPOSE="${DEEP_LEARNING_COMPOSE:-workloads/examples/k8s/deep-learning-examples/docker-compose.yaml}"


function help_me() {
    echo "This script creates a deployment of one of NVIDIA's DeepLearningExamples."
    echo "  (https://github.com/NVIDIA/DeepLearningExamples)"
    echo "Example:"
    echo "  ./scripts/k8s/deep-learning-examples/deploy-deeep-learning-example.sh -c tensorflow2-recommendation-wideanddeep"
    echo ""
    echo "Usage:"
    echo "-(d)elete      Delete a named deployment, if it exists."
    echo "-(h)elp        This message."
    echo "-(c)reate      Define a named experiment to run, one of:"
    echo " - cuda-optimized-fastspeech"
    echo " - dglpytorch-drugdiscovery-se3transformer"
    echo " - kaldi-speechrecognition (Work in Progress)"
    echo " - mxnet-classification"
    echo " - pytorch-classification-convnets"
    echo " - pytorch-detection-efficientdet"
    echo " - pytorch-detection-ssd"
    echo " - pytorch-forecasting-tft"
    echo " - pytorch-languagemodeling-bart"
    echo " - pytorch-languagemodeling-bert"
    echo " - pytorch-languagemodeling-transformer-xl"
    echo " - pytorch-recommendation-dlrm"
    echo " - pytorch-recommendation-ncf"
    echo " - pytorch-segmentation-maskrcnn"
    echo " - pytorch-segmentation-nnunet"
    echo " - pytorch-speechrecognition-jasper"
    echo " - pytorch-speechrecognition-quartznet"
    echo " - pytorch-speechsynthesis-fastpitch"
    echo " - pytorch-speechsynthesis-tacotron2"
    echo " - pytorch-translation-gnmt"
    echo " - pytorch-translation-transformer"
    echo " - tensorflow-classification-convnets"
    echo " - tensorflow-detection-ssd"
    echo " - tensorflow-languagemodeling-bert"
    echo " - tensorflow-languagemodeling-transformerxl"
    echo " - tensorflow-recommendation-ncf"
    echo " - tensorflow-recommendation-vaecf"
    echo " - tensorflow-recommendation-wideanddeep"
    echo " - tensorflow-segmentation-unet3dmedical"
    echo " - tensorflow-segmentation-unetindustrial"
    echo " - tensorflow-segmentation-unetmedical"
    echo " - tensorflow-segmentation-vnet"
    echo " - tensorflow-translation-gnmt"
    echo " - tensorflow2-efficientnet"
    echo " - tensorflow2-languagemodeling-bert"
    echo " - tensorflow2-languagemodeling-electra"
    echo " - tensorflow2-recommendation-dlrm"
    echo " - tensorflow2-recommendation-wideanddeep"
    echo " - tensorflow2-segmentation-maskrcnn"
    echo " - tensorflow2-segmentation-unet-medical"
}


function get_opts() {
    while getopts "c:d:h" option; do
        case $option in
            h)
                help_me
                exit 1
                ;;
            c)
                export DLE_DEPLOYMENT="$OPTARG"
                echo "Deploying the ${DLE_DEPLOYMENT} service."
                ;;
            d)
                export DLE_DEPLOYMENT="$OPTARG"
                sudo kubectl -f "${DEEP_LEARNING_DIR}${DLE_DEPLOYMENT}.yaml" delete --wait
                exit 0
                ;;
        esac
    done
}

function build_image(){
    echo "Building the image for ${DLE_DEPLOYMENT}"
    docker-compose --file=${DEEP_LEARNING_COMPOSE} build ${DLE_DEPLOYMENT}
    docker-compose --file=${DEEP_LEARNING_COMPOSE} push ${DLE_DEPLOYMENT} 
}

function deploy_service(){
    
    echo "You can remove this service from the cluster by running the following:"
    echo "  ansible-playbook -l k8s-cluster playbooks/k8s-cluster/deep-learning-examples.yaml -e 'action=d nvdle=${DLE_DEPLOYMENT}'"
    sudo kubectl -f "${DEEP_LEARNING_DIR}${DLE_DEPLOYMENT}.yaml" delete --wait > /dev/null 2>&1
    sudo kubectl -f "${DEEP_LEARNING_DIR}${DLE_DEPLOYMENT}.yaml" create
    sudo kubectl get all -n ${DLE_DEPLOYMENT}
}


function get_ips(){
    # Get IP information
    master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)
    ingress_ip_string="$(echo ${master_ip} | tr '.' '-').nip.io"
}


function print_nodeport() {
    get_ips
    jupyterlab_port=$(kubectl -n ${DLE_DEPLOYMENT} get svc ${DLE_DEPLOYMENT} --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)
    export jupyterlab_url="http://${master_ip}:${jupyterlab_port}/"
    echo
    echo "${DLE_DEPLOYMENT} jupyterlab: ${jupyterlab_url}"
}


get_opts ${@}

if [ ${DLE_DEPLOYMENT} == 0 ]; 
    then
        help_me
        exit 0
    else
        build_image
        deploy_service
        print_nodeport
fi
