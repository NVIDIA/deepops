Getting Started
===

## What is DeepOps?

The DeepOps project is a reference approach for provisioning and deploying GPU servers and multi-node GPU clusters. It is intended to be adapted to unique environments and requirements while helping you go faster by sharing the experience we have with GPU servers and NVIDIA SW stacks applied to our HPC and DL needs.

## How to use DeepOps

The structure of this DeepOps repository will evolve over time to improve usefulness and keep up with industry innovation.  The current baseline is heavy on flexibility and light on OOB easeof-use, but delivers speed of deployment and optimal GPU performance. To help on ease-of-use, here’s an outline to follow in using DeepOps.

The simplistic view of steps you follow with DeepOps are listed below. Any of these steps might be omitted, modified, and additional steps added as you see fit. There’s no one approach to DeepOps so expect to make it your own:

1. Bootstrap an environment to customize and launch DeepOps assisted GPU cluster provisioning, configuration, and operation. Think of this as gathering the materials and tools to build your house. DeepOps assumes that you will have a provisioning node for running Ansible, management/login nodes for running Kubernetes and/or Slurm, and compute nodes for performing training and/or inference.

2. Design and define the GPU cluster you want to build. These steps are an exercise left to you. There are more options in DeepOps that you will likely need.  We will help you by asking some of the important questions we found helpful to quickly narrowing down the parts, configurations, and actions needed to use DeepOps effectively.

3. Deploy and test your baseline GPU cluster. We say baseline because our GPU clusters have always been a living thing that will grow and adapt over time. DeepOps is intended to help you scale and adapt quickly, deterministically to taking advantage of NVIDIA software innovations.

> Included with DeepOps is a reference way to virtually deploy on a single machine. It’s  a quick way to test a conceptual GPU cluster design with minimal resource requirements and risk of disrupting your physical infrastructure. It is also a great tool for debugging your customizing of DeepOps scripts before you touch real metal.

4. Operate and monitor your GPU cluster so your users solve the hard problems we all want solved. Things will break, new challenges will come, we use DeepOps as our tool for adapting infrastructure fast so users can keep working fast.
