# DeepOps Testing, CI/CD, and Validation

## DeepOps Continuous Integration Testing

The DeepOps project leverages a private Jenkins server to run continuous integration tests. Testing is done using the [virtual](../../virtual) deployment mechanism. Several Vagrant VMs are created, the cluster is deployed, tests are executed, and then the VMs are destroyed. 

The goal of the DeepOps CI is to prevent bugs from being introduced into the code base and to identify when changes in 3rd party platforms have occurred or impacted the DeepOps deployment mechanisms. In general, K8s and Slurm deployment issues are detected and resolved with urgency. Many components of DeepOps are 3rd party open source tools that may silently fail or suddenly change without notice. The team will make a best-effort to resolve these issues and include regression tests, however there may be times where a fix is unavailable. Historically, this has been an issue with Rook-Ceph and Kubeflow, and those GitHub communities are best equipped to help with resolutions. 

### Testing Methodi

DeepOps CI contains two types of automated tests:

* Nightly tests. These are more exhaustive and run on a nightly basis against the `master` branch.

* PR tests. These are faster and are executed against every open PR when commits are made to `master`. They are also when a commit is made to any DeepOps branch (`release-20.12`, `master`, etc.). Results are integrated into GitHub.

### Tests

A short description of the nightly testing is outlined below. The full suit of tests can be reviewed in the [jenkins](../../workloads/jenkins) directory. Additional details can be found [here](../../workloads/jenkins/README.md).


**Testing Matrix**

| Test | [PR](../../workloads/jenkins/Jenkinsfile) | [Nightly](../../workloads/jenkins/Jenkinsfile-nightly) | [Nightly Multi-node](../../workloads/jenkins/Jenkinsfile-multi-nightly) | Comments |
| --- | --- | --- | --- | --- |
| Ubuntu 18.04 | x | x | x | |
| Ubuntu 20.04 | | | | Support planned |
| CentOS 7 | | x | x | |
| DGX OS | | | | No automated testing support |
| RHEL | | | | No testing support |
| 1 mgmt node | x | x | | |
| 3 mgmt nodes | | | x | |
| 1 gpu node | x | x | | |
| 2 gpu nodes | | | x | |
| Deploys Slurm | x | x | x | |
| Verify GPU workload with srun | x | x | x |
| Verify Slurm nfs mount | x | x | x | |
| Verify basic mpi job in Slurm | x | x | x | |
| Deploys K8s (No GPU Operator) | x | x | x | |
| Deploy & validate K8s (GPU Operator) | | x | x | |
| Verify Device Plugin is working | x | x | x |
| Verify GPU Feature Discovery is labeling nodes | x | x | x |
| Verify GPU workload in K8s | x | x | x |
| Verifies Ingress configuration | x | x |
| Verifies local Docker registry | x | x | x |
| Verifies local Docker mirror | x | x | x |
| Verify Grafana loads (no metric verification | x | x | x |
| Verify GPU dashboard loads | x | x | x |
| Test Kubeflow deployment (with Dex) | | x | x |
| Test Kubeflow deployment (without Dex) | | x | x |
| Execute GPU workload with Kubeflow pipeline | | x | x |
| Airgap testing | | | | No testing support
| Verify multinode job in K8s | | | | No testing support
| Verify Ceph deployment | | | | Support dropped
| MAAS Deployment | | | | Used regularly, no automated testing
| MIG configuration | | | | No testing support


## DeepOps Deployment Validation

The Slurm and Kubernetes deployment guides both document cluster verification steps. These should be run during the installation process to validate a GPU workload can be executed on the cluster.

Additional services such as Kubeflow, Open OnDemand, or Monitoring may have additional validation steps that are documented in the corresponding DeepOps READMEs and the official documentation.

For workloads that can be used as post-deployment validation, see the example workloads for [k8s]( ../../workloads/examples/k8s/) and [slurm]( ../../workloads/examples/slurm).
