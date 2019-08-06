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
          echo "Munge files for testing"
          sh '''
            bash -x ./.jenkins-scripts/munge-files.sh
          '''

          echo "Cluster Up"
          sh '''
            bash -x ./.jenkins-scripts/test-cluster-up.sh
          '''

          echo "Verify we can run a GPU job"
          sh '''
            bash -x ./.jenkins-scripts/run-gpu-job.sh
          '''

          echo "Verify ingress config"
          sh '''
             bash -x ./.jenkins-scripts/verify-ingress-config.sh
          '''

          echo "Set up Slurm"
          sh '''
            pwd
            cd virtual
            ./scripts/setup_slurm.sh
          '''

          echo "Test Slurm"
          sh '''
            bash -x ./.jenkins-scripts/test-slurm-job.sh
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
