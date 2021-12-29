# NVIDIA Deep Learning Examples for Tensor Cores

## Introduction

This repository provides State-of-the-Art Deep Learning examples that are easy to train and deploy, achieving the best reproducible accuracy and performance with NVIDIA CUDA-X software stack running on NVIDIA Volta, Turing and Ampere GPUs.

## NVIDIA GPU Cloud (NGC) Container Registry

These examples, along with our NVIDIA deep learning software stack, are provided in a monthly updated Docker container on the NGC container registry (https://ngc.nvidia.com). These containers include:

- The latest NVIDIA examples from this repository
- The latest NVIDIA contributions shared upstream to the respective framework
- The latest NVIDIA Deep Learning software libraries, such as cuDNN, NCCL, cuBLAS, etc. which have all been through a rigorous monthly quality assurance process to ensure that they provide the best possible performance
- [Monthly release notes](https://docs.nvidia.com/deeplearning/dgx/index.html#nvidia-optimized-frameworks-release-notes) for each of the NVIDIA optimized containers

## DeepOps Deployment Options

Once you've set up a working cluster, you may use the provided script to deploy a jupyter lab session on node port 30888.

```bash
./scripts/k8s/deep-learning-examples/deploy-deeep-learning-example.sh -c pytorch-detection-ssd
```

### Deployment Creation Options:

    - pytorch-classification-convnets
    - pytorch-detection-efficientdet
    - pytorch-detection-ssd
    - pytorch-forecasting-tft
    - pytorch-languagemodeling-bart
    - pytorch-languagemodeling-bert
    - pytorch-languagemodeling-transformer-xl
    - pytorch-recommendation-dlrm
    - pytorch-recommendation-ncf
    - pytorch-segmentation-maskrcnn
    - pytorch-segmentation-nnunet
    - pytorch-speechrecognition-jasper
    - pytorch-speechrecognition-quartznet
    - pytorch-speechsynthesis-fastpitch
    - pytorch-speechsynthesis-tacotron2
    - pytorch-translation-gnmt
    - pytorch-translation-transformer
    - tensorflow-efficientnet
    - tensorflow-languagemodeling-bert
    - tensorflow-languagemodeling-electra
    - tensorflow-recommendation-dlrm
    - tensorflow-recommendation-wideanddeep
    - tensorflow-segmentation-maskrcnn
    - tensorflow-segmentation-unet-medical

## Glossary

**Multinode Training**  
Supported on a pyxis/enroot Slurm cluster.

**Deep Learning Compiler (DLC)**  
TensorFlow XLA and PyTorch JIT and/or TorchScript

**Accelerated Linear Algebra (XLA)**  
XLA is a domain-specific compiler for linear algebra that can accelerate TensorFlow models with potentially no source code changes. The results are improvements in speed and memory usage.

**PyTorch JIT and/or TorchScript**  
TorchScript is a way to create serializable and optimizable models from PyTorch code. TorchScript, an intermediate representation of a PyTorch model (subclass of nn.Module) that can then be run in a high-performance environment such as C++.

**Automatic Mixed Precision (AMP)**  
Automatic Mixed Precision (AMP) enables mixed precision training on Volta, Turing, and NVIDIA Ampere GPU architectures automatically.

**TensorFloat-32 (TF32)**  
TensorFloat-32 (TF32) is the new math mode in [NVIDIA A100](https://www.nvidia.com/en-us/data-center/a100/) GPUs for handling the matrix math also called tensor operations. TF32 running on Tensor Cores in A100 GPUs can provide up to 10x speedups compared to single-precision floating-point math (FP32) on Volta GPUs. TF32 is supported in the NVIDIA Ampere GPU architecture and is enabled by default.

**Jupyter Notebooks (NB)**  
The Jupyter Notebook is an open-source web application that allows you to create and share documents that contain live code, equations, visualizations and narrative text.
