# Testing

DeepOps Testing, CI/CD, and Validation

- [Testing](#testing)
  - [Linting](#linting)
  - [DeepOps end-to-end testing](#deepops-end-to-end-testing)
    - [Testing Method](#testing-method)
    - [Tests](#tests)
  - [DeepOps Ansible role testing](#deepops-ansible-role-testing)
    - [Defining Molecule tests for a new role](#defining-molecule-tests-for-a-new-role)
  - [DeepOps Deployment Validation](#deepops-deployment-validation)

## Linting

`ansible-lint` is automatically run for each role in the `roles/` directory using a [Github action](../../.github/workflows/ansible-lint-roles.yml).
This action runs `ansible-lint` for each role, and provides both the full output and a list of roles that failed linting.
If the Github action reports success, all roles should have passed linting.

The linting process can also be executed manually in a checkout of the DeepOps repo,
by running `./scripts/deepops/ansible-lint-roles.sh`.

Note that the linting script can be configured to skip a subset of roles,
by providing a regex of roles to skip in the envionment variable `ANSIBLE_LINT_EXCLUDE`.
(For example, `ANSIBLE_LINT_EXCLUDE='role-1|role-2|role-3'`.)
This can be useful for excluding specific roles that have known issues or are still in development.

## DeepOps end-to-end testing

The DeepOps project leverages a private Jenkins server to run continuous integration tests. Testing is done using the [virtual](../../virtual) deployment mechanism. Several Vagrant VMs are created, the cluster is deployed, tests are executed, and then the VMs are destroyed.

The goal of the DeepOps CI is to prevent bugs from being introduced into the code base and to identify when changes in 3rd party platforms have occurred or impacted the DeepOps deployment mechanisms. In general, K8s and Slurm deployment issues are detected and resolved with urgency. Many components of DeepOps are 3rd party open source tools that may silently fail or suddenly change without notice. The team will make a best-effort to resolve these issues and include regression tests, however there may be times where a fix is unavailable. Historically, this has been an issue with Rook-Ceph and Kubeflow, and those GitHub communities are best equipped to help with resolutions.

### Testing Method

DeepOps CI contains two types of automated tests:

- Nightly tests. These are more exhaustive and run on a nightly basis against the `master` branch.

- PR tests. These are faster and are executed against every open PR when commits are made to `master`. They are also when a commit is made to any DeepOps branch (`release-20.12`, `master`, etc.). Results are integrated into GitHub.

In addition to the automated tests, we also provide developers the a method to manually kick off a test run against one or more deployment configurations in parallel from the below testing matrix through the [Jenkins-matrix](../../workloads/jenkins/Jenkinsfile-matrix) Jenkinsfile.

### Tests

A short description of the nightly testing is outlined below. The full suit of tests can be reviewed in the [jenkins](../../workloads/jenkins) directory. Additional details can be found [here](../../workloads/jenkins/README.md).

**Testing Matrix**

| Test                                                | [PR](../../workloads/jenkins/Jenkinsfile) | [Nightly](../../workloads/jenkins/Jenkinsfile-nightly) | [Nightly Multi-node](../../workloads/jenkins/Jenkinsfile-multi-nightly) | Comments                             |
| --------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------- | ------------------------------------ |
| Ubuntu 18.04                                        | x                                         | x                                                      | x                                                                       |                                      |
| Ubuntu 20.04                                        |                                           | x                                                      | x                                                                       |                                      |
| CentOS 7                                            |                                           | x                                                      | x                                                                       |                                      |
| CentOS                                              |                                           |                                                        | x                                                                       |                                      |
| DGX OS                                              |                                           |                                                        |                                                                         | No automated testing support         |
| RHEL                                                |                                           |                                                        |                                                                         | No testing support                   |
| 1 mgmt node                                         | x                                         | x                                                      |                                                                         |                                      |
| 3 mgmt nodes                                        |                                           |                                                        | x                                                                       |                                      |
| 1 gpu node                                          | x                                         | x                                                      |                                                                         |                                      |
| 2 gpu nodes                                         |                                           |                                                        | x                                                                       |                                      |
| Deploys Slurm                                       | x                                         | x                                                      | x                                                                       |                                      |
| Verify GPU workload with srun                       | x                                         | x                                                      | x                                                                       |
| Verify Slurm nfs mount                              | x                                         | x                                                      | x                                                                       |                                      |
| Verify basic mpi job in Slurm                       | x                                         | x                                                      | x                                                                       |                                      |
| Verify basic enroot job in Slurm                    | x                                         | x                                                      | x                                                                       | x                                    |
| Verify rsyslog setup in Slurm                       | x                                         | x                                                      | x                                                                       |                                      |
| Verify rsyslog setup in K8s                         | x                                         | x                                                      | x                                                                       |                                      |
| Deploys K8s (No GPU Operator)                       | x                                         | x                                                      | x                                                                       |                                      |
| Deploy & validate K8s (GPU Operator)                |                                           | x                                                      | x                                                                       |                                      |
| Verify Device Plugin is working                     | x                                         | x                                                      | x                                                                       |
| Verify GPU Feature Discovery is labeling nodes      | x                                         | x                                                      | x                                                                       |
| Verify GPU workload in K8s                          | x                                         | x                                                      | x                                                                       |
| Verifies Ingress configuration                      | x                                         | x                                                      |
| Verifies local Docker registry                      | x                                         | x                                                      | x                                                                       |
| Verifies local Docker mirror                        | x                                         | x                                                      | x                                                                       |
| Verify Grafana loads (no metric verification        | x                                         | x                                                      | x                                                                       |
| Verify GPU dashboard loads                          | x                                         | x                                                      | x                                                                       |
| Test Kubeflow deployment (with Dex)                 |                                           | x                                                      | x                                                                       |
| Test Kubeflow deployment (without Dex)              |                                           | x                                                      | x                                                                       |
| Execute GPU workload with Kubeflow pipeline         |                                           | x                                                      | x                                                                       |
| Verify GPU dashboard metrics are configured in DCGM | x                                         | x                                                      | x                                                                       | x                                    |
| Airgap testing                                      |                                           |                                                        |                                                                         | No testing support                   |
| Verify multinode job in K8s                         |                                           |                                                        |                                                                         | No testing support                   |
| Verify Ceph deployment                              |                                           |                                                        |                                                                         | Support dropped                      |
| MAAS Deployment                                     |                                           |                                                        |                                                                         | Used regularly, no automated testing |
| MIG configuration                                   |                                           |                                                        |                                                                         | No testing support                   |

## DeepOps Ansible role testing

A subset of the Ansible roles in DeepOps have tests defined using [Ansible Molecule](https://molecule.readthedocs.io/en/latest/).
This testing mechanism allows the roles to be tested individually, providing additional test signal to identify issues which do not appear in the end-to-end tests.
These tests are run automatically for each pull request using [Github Actions](https://github.com/NVIDIA/deepops/actions).

Molecule testing runs the Ansible role in quesiton inside a Docker container.
As such, not all roles will be easy to test witth this mechanism.
Roles which mostly involve installing software, configuring services, or executing scripts should generally be possible to test.
Roles which rely on the presence of specific hardware (such as GPUs), which reboot the nodes they act on, or which make changes to kernel configuration are going to be harder to test with Molecule.

### Defining Molecule tests for a new role

To add Molecule tests to a new role, the following procedure can be used.

1. Ensure you have Docker installed in your development environment

2. Install Ansible Molecule and `community.docker` Ansible Galaxy collection in your development environment

```
$ python3 -m pip install "molecule[docker,lint]"
$ ansible-galaxy collection install community.docker
```

3. Initialize Molecule in your new role

```bash
cd deepops/roles/<your-role>
molecule init scenario -r <your-role> --driver-name docker
```

4. In the file `molecule/default/molecule.yml`, define the list of platforms to be tested.
   DeepOps currently supports operating systems based on Ubuntu 18.04, Ubuntu 20.04, EL7, and EL8.
   To test these stacks, the following `platforms` stanza can be used.

```yaml
platforms:
  - name: ubuntu-1804
    image: geerlingguy/docker-ubuntu1804-ansible
    pre_build_image: true
  - name: ubuntu-2004
    image: geerlingguy/docker-ubuntu2004-ansible
    pre_build_image: true
  - name: centos-7
    image: geerlingguy/docker-centos7-ansible
    pre_build_image: true
  - name: centos-8
    image: geerlingguy/docker-centos8-ansible
    pre_build_image: true
```

5. If you haven't already, define your role's metadata in the file `meta/main.yml`.
   A sample `meta.yml` is shown here:

```yaml
galaxy_info:
  role_name: <your-role>
  namespace: deepops
  author: DeepOps Team
  company: NVIDIA
  description: <your-description>
  license: 3-Clause BSD
  min_ansible_version: 2.9
```

6. Once this is done, verify that your role executes successfully in the Molecule environment by running `molecule test`. If you run into any issues, consult the [Molecule documentation](https://molecule.readthedocs.io/en/latest/index.html) for help resolving them.

7. (optional) In addition to testing successful execution, you can add additional tests which will be run after your role completes in a file `molecule/default/verify.yml`. This is an Ansible playbook that will run in the same environment as your playbook ran. For a simple example of such a verify playbook, see the [Enroot role](https://github.com/NVIDIA/ansible-role-enroot/blob/master/molecule/default/verify.yml).

8. Once you're confident that your new tests are all passing, add your role to the `deepops-role` section in the `.github/workflows/molecule.yml` file.

## DeepOps Deployment Validation

The Slurm and Kubernetes deployment guides both document cluster verification steps. These should be run during the installation process to validate a GPU workload can be executed on the cluster.

Additional services such as Kubeflow, Open OnDemand, or Monitoring may have additional validation steps that are documented in the corresponding DeepOps READMEs and the official documentation.

For workloads that can be used as post-deployment validation, see the example workloads for [k8s](../../workloads/examples/k8s/) and [slurm](../../workloads/examples/slurm).
