pipeline {
  agent any
  stages {
    stage('Cluster Up') {
      steps {
        sh '''pwd
cd virtual
cp /opt/deepops_test/Vagrantfile .
./setup.sh
./cluster_up.sh'''
      }
    }
    stage('Test') {
      steps {
        sh '''export KUBECONFIG=virtual/k8s-config/artifacts/admin.conf
export PATH="$(pwd)/virtual/k8s-config/artifacts:${PATH}"
kubectl get nodes
kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi'''
      }
    }
    stage('Cluster Destroy') {
      steps {
        sh '''cd virtual
./cluster_destroy.sh'''
      }
    }
  }
}