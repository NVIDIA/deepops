DeepOps Offline Scripts
=======================

## UNDER CONSTRUCTION

**This workflow is currently a work-in-progress and probably doesn't fully work!
Please be aware when testing scripts in this directory.**

One goal of DeepOps is to support running "offline", in an environment in which the nodes do not have access to the Internet.
This environment may be completely disconnected, i.e. behind an air gap, so that there is no mechanism for online data transfer at all.

In order to stand up an offline environment, we need to be able to:

1. Download all required dependencies, such as OS packages, container images, and Helm charts.
1. Package these up in a convenient fashion for offline file transfer.
1. After file transfer, set up local mirrors of repositories and download sites.
1. Run the DeepOps turnup process using the local mirrors.
