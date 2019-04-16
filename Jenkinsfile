pipeline {
  agent any
  stages {
    stage('Stop Any Old Builds') {
      steps {
        milestone label: '', ordinal:  Integer.parseInt(env.BUILD_ID) - 1
        milestone label: '', ordinal:  Integer.parseInt(env.BUILD_ID)
      }
    }
    stage('Cluster Up') {
      steps {
        // TODO: ideally lock should work with declared stages
        lock(resource: null, label: 'gpu', quantity: 1, variable: 'GPUDATA') {
          echo "Modifying Vagrantfiles"
          sh '''
            pwd
            export GPU="$(echo ${GPUDATA} | cut -d"-" -f1)"
            export BUS="$(echo ${GPUDATA} | cut -d"-" -f2)"
            # modify GPU passthrough to point to this resource's GPU
            sed -i -e "s/#v.pci :bus => '0x08', :slot => '0x00', :function => '0x0'/v.pci :bus => '$BUS', :slot => '0x00', :function => '0x0'/g" virtual/Vagrant*
            # modify CPU and RAM requirements
            git grep -lz "v.cpus = 2" virtual/ | xargs -0 sed -i -e "s/v.cpus = 2/v.cpus = 4/g"
            git grep -lz "v.memory = 2048" virtual/ | xargs -0 sed -i -e "s/v.memory = 2048/v.memory = 16384/g"
            # modify machine names and IPs
            git grep -lz virtual-mgmt virtual/ | xargs -0 sed -i -e "s/virtual-mgmt/virtual-mgmt-$GPU/g"
            git grep -lz virtual-login virtual/ | xargs -0 sed -i -e "s/virtual-login/virtual-login-$GPU/g"
            git grep -lz virtual-gpu01 virtual/ | xargs -0 sed -i -e "s/virtual-gpu01/virtual-gpu01-$GPU/g"
            git grep -lz 10.0.0.2 virtual/ | xargs -0 sed -i -e "s/10.0.0.2/10.0.0.2$GPU/g"
            git grep -lz 10.0.0.4 virtual/ | xargs -0 sed -i -e "s/10.0.0.4/10.0.0.4$GPU/g"
            git grep -lz 10.0.0.11 virtual/ | xargs -0 sed -i -e "s/10.0.0.11/10.0.0.11$GPU/g"
            sed -i -e "s/virtual_virtual-mgmt/virtual_virtual-mgmt-$GPU/g" virtual/vagrant_shutdown.sh
            sed -i -e "s/virtual_virtual-login/virtual_virtual-login-$GPU/g" virtual/vagrant_shutdown.sh
            sed -i -e "s/virtual_virtual-gpu01/virtual_virtual-gpu01-$GPU/g" virtual/vagrant_shutdown.sh
          '''

          echo "Modifying loadbalancer config to use unique IPs"
          sh '''
            pwd
            export GPU="$(echo ${GPUDATA} | cut -d"-" -f1)"
            cat config.example/helm/metallb.yml
            sed -i -e  "s/10\\.0\\.0\\.100-10\\.0\\.0\\.110$/10.0.0.1${GPU}0-10.0.0.1${GPU}9/g" config.example/helm/metallb.yml
            cat config.example/helm/metallb.yml
          '''

          echo "Increase debug scope for ansible-playbook commands"
          sh '''
            sed -i -e "s/ansible-playbook/ansible-playbook -v/g" virtual/scripts/*
          '''

          echo "Cluster Up"
          sh '''
            pwd
            cd virtual
            ./vagrant_startup.sh
            export DEEPOPS_FORCE_DNS=0
            ./cluster_up.sh
          '''

          // TODO: Use junit-style tests
          echo "Verify we can run a GPU job"
          sh '''
            cd virtual
            export K8S_CONFIG_DIR=$(pwd)/k8s-config
            export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
            export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"
            chmod 755 $K8S_CONFIG_DIR/artifacts/kubectl
            kubectl get nodes
            kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi
          '''

          echo "Verify ingress config"
          sh '''
            cd virtual
            export K8S_CONFIG_DIR="$(pwd)/k8s-config"
            export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
            export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"
            chmod 755 $K8S_CONFIG_DIR/artifacts/kubectl
            cat config/helm/metallb.yml
            cat config/helm/ingress.yml
            kubectl describe service nginx-ingress-controller
            kubectl describe pod -l app=metallb,component=controller
            kubectl get pods
            kubectl get services --all-namespaces
            sleep 30
            kubectl get pods
            kubectl get services
            nginx_external_ip=$(kubectl get services -l app=nginx-ingress,component=controller --no-headers | awk '{print $4}')
            curl "http://${nginx_external_ip}/" 
          '''

          echo "Set up Slurm"
          sh '''
            pwd
            cd virtual
            ./scripts/setup_slurm.sh
          '''

          echo "Test Slurm"
          sh '''
            pwd
            export GPU="$(echo ${GPUDATA} | cut -d"-" -f1)"
            ssh -v -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -l vagrant -i $HOME/.ssh/id_rsa 10.0.0.4$GPU srun -n1 hostname
          '''
        }
      }
    }
  }
  post {
    always {
      sh '''
        pwd
        cd virtual && ./vagrant_shutdown.sh
      '''
    }
  }
}
