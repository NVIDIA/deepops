Role Name
=========
# NVIDIA GPU Tests Role

This role is meant to be a quick tool for system validation or simple system burn in. It should not be used as a comprehensive performance test.

Running this will perform the following:

* Install the CUDA toolkit
* Download and build cuda-samples
* Run the Peer2Peer and MatrixMultiply tests
* Run the DCGM diagnostics (set `gpu_test_dcgm_fail_on_error: yes` to fail the play when `dcgmi diag` exits non-zero; by default failures are ignored)
* Run a basic Tensorflow DL job


# Requirements

This role can be applied to a heterogeneous cluster of GPU nodes.

The following should be installed on the system prior to running this role (these come standard in the DGX Operating System):

* CUDA toolkit
* dcgmi
* nvidia-docker
* docker

