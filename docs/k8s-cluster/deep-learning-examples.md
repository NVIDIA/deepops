# Deep Learning Examples

- [Deep Learning Examples](#deep-learning-examples)
  - [Introduction](#introduction)
  - [DeepOps Deployment Options](#deepops-deployment-options)
    - [Deployment Example Name Options:](#deployment-example-name-options)
  - [Performance](#performance)
    - [Computer Vision](#computer-vision)
    - [Natural Language Processing](#natural-language-processing)
    - [Recommender Systems](#recommender-systems)
    - [Speech to Text](#speech-to-text)
    - [Text to Speech](#text-to-speech)
    - [Graph Neural Networks](#graph-neural-networks)

## Introduction

This repository provides NVIDIA's State-of-the-Art Deep Learning examples that are easy to train and deploy, achieving the best reproducible accuracy and performance with NVIDIA CUDA-X software stack running on NVIDIA Volta, Turing and Ampere GPUs.

## DeepOps Deployment Options

Once the cluster, and a [local docker registry](../../playbooks/k8s-cluster/container-registry.yml) are accessible by all nodes (default is port `registry.local:31500`, use helm to deploy a jupyter lab session which will be exposed via NodePort (default port is `30888`).

```bash
helm install <DEPLOYMENT_EXAMPLE_NAME> workloads/examples/k8s/deep-learning-examples --set exampleName=<DEPLOYMENT_EXAMPLE_NAME>
```

Deployment modifications may be made using the `--set` flag or directly in the values.yaml.
See the [values.yaml](../../workloads/examples/k8s/deep-learning-examples/values.yaml) file for more detail on the available configuration.

### Deployment Example Name Options:
```yaml
- cuda-optimized-fastspeech
- dglpytorch-drugdiscovery-se3transformer
- mxnet-classification
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
- tensorflow-classification-convnets
- tensorflow-detection-ssd
- tensorflow-languagemodeling-bert
- tensorflow-languagemodeling-transformerxl
- tensorflow-recommendation-ncf
- tensorflow-recommendation-vaecf
- tensorflow-recommendation-wideanddeep
- tensorflow-segmentation-unet3dmedical
- tensorflow-segmentation-unetindustrial
- tensorflow-segmentation-unetmedical
- tensorflow-segmentation-vnet
- tensorflow-translation-gnmt
- tensorflow2-efficientnet
- tensorflow2-languagemodeling-bert
- tensorflow2-languagemodeling-electra
- tensorflow2-recommendation-dlrm
- tensorflow2-recommendation-wideanddeep
- tensorflow2-segmentation-maskrcnn
- tensorflow2-segmentation-unet-medical
```

## Performance

### Computer Vision

| Models                                                                                                                              | Framework   | A100 | AMP | Multi-GPU | Multi-Node | TRT | ONNX | Triton                                                                                                                       | DLC | NB                                                                                                                                                               |
| ----------------------------------------------------------------------------------------------------------------------------------- | ----------- | ---- | --- | --------- | ---------- | --- | ---- | ---------------------------------------------------------------------------------------------------------------------------- | --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [ResNet-50](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/resnet50v1.5)                | PyTorch     | Yes  | Yes | Yes       | -          | Yes | -    | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/triton/resnet50)            | Yes | -                                                                                                                                                                |
| [ResNeXt-101](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/resnext101-32x4d)          | PyTorch     | Yes  | Yes | Yes       | -          | Yes | -    | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/triton/resnext101-32x4d)    | Yes | -                                                                                                                                                                |
| [SE-ResNeXt-101](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/se-resnext101-32x4d)    | PyTorch     | Yes  | Yes | Yes       | -          | Yes | -    | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/triton/se-resnext101-32x4d) | Yes | -                                                                                                                                                                |
| [EfficientNet-B0](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/efficientnet)          | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [EfficientNet-B4](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/efficientnet)          | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [EfficientNet-WideSE-B0](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/efficientnet)   | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [EfficientNet-WideSE-B4](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Classification/ConvNets/efficientnet)   | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [Mask R-CNN](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Segmentation/MaskRCNN)                              | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | -   | [Yes](https://github.com/NVIDIA/DeepLearningExamples/blob/master/PyTorch/Segmentation/MaskRCNN/pytorch/notebooks/pytorch_MaskRCNN_pyt_train_and_inference.ipynb) |
| [nnUNet](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Segmentation/nnUNet)                                    | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [SSD](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Detection/SSD)                                             | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | -   | [Yes](https://github.com/NVIDIA/DeepLearningExamples/blob/master/PyTorch/Detection/SSD/examples/inference.ipynb)                                                 |
| [ResNet-50](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Classification/ConvNets/resnet50v1.5)             | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [ResNeXt101](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Classification/ConvNets/resnext101-32x4d)        | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [SE-ResNeXt-101](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Classification/ConvNets/se-resnext101-32x4d) | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [Mask R-CNN](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/Segmentation/MaskRCNN)                          | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [SSD](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Detection/SSD)                                          | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | [Yes](https://github.com/NVIDIA/DeepLearningExamples/blob/master/TensorFlow/Detection/SSD/models/research/object_detection/object_detection_tutorial.ipynb)      |
| [U-Net Ind](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Segmentation/UNet_Industrial)                     | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Segmentation/UNet_Industrial/notebooks)                                              |
| [U-Net Med](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Segmentation/UNet_Medical)                        | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [U-Net 3D](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Segmentation/UNet_3D_Medical)                      | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [V-Net Med](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Segmentation/VNet)                                | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [U-Net Med](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/Segmentation/UNet_Medical)                       | TensorFlow2 | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [Mask R-CNN](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/Segmentation/MaskRCNN)                          | TensorFlow2 | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [EfficientNet](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/Classification/ConvNets/efficientnet)         | TensorFlow2 | Yes  | Yes | Yes       | Yes        | -   | -    | -                                                                                                                            | Yes | -                                                                                                                                                                |
| [ResNet-50](https://github.com/NVIDIA/DeepLearningExamples/tree/master/MxNet/Classification/RN50v1.5)                               | MXNet       | -    | Yes | Yes       | -          | -   | -    | -                                                                                                                            | -   | -                                                                                                                                                                |

### Natural Language Processing

| Models                                                                                                                 | Framework   | A100 | AMP | Multi-GPU | Multi-Node | TRT | ONNX | Triton                                                                                                    | DLC | NB                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------------------------- | ----------- | ---- | --- | --------- | ---------- | --- | ---- | --------------------------------------------------------------------------------------------------------- | --- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| [BERT](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/LanguageModeling/BERT)                       | PyTorch     | Yes  | Yes | Yes       | Yes        | -   | -    | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/LanguageModeling/BERT/triton)    | Yes | -                                                                                                                                           |
| [TransformerXL](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/LanguageModeling/Transformer-XL)    | PyTorch     | Yes  | Yes | Yes       | Yes        | -   | -    | -                                                                                                         | Yes | -                                                                                                                                           |
| [GNMT](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Translation/GNMT)                            | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                         | -   | -                                                                                                                                           |
| [Transformer](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Translation/Transformer)              | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                         | -   | -                                                                                                                                           |
| [ELECTRA](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/LanguageModeling/ELECTRA)             | TensorFlow2 | Yes  | Yes | Yes       | Yes        | -   | -    | -                                                                                                         | Yes | -                                                                                                                                           |
| [BERT](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/LanguageModeling/BERT)                    | TensorFlow  | Yes  | Yes | Yes       | Yes        | Yes | -    | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/LanguageModeling/BERT/triton) | Yes | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/LanguageModeling/BERT/notebooks)                                |
| [BERT](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/LanguageModeling/BERT)                   | TensorFlow2 | Yes  | Yes | Yes       | Yes        | -   | -    | -                                                                                                         | Yes | -                                                                                                                                           |
| [BioBert](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/LanguageModeling/BERT/biobert)         | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                         | Yes | [Yes](https://github.com/NVIDIA/DeepLearningExamples/blob/master/TensorFlow/LanguageModeling/BERT/notebooks/biobert_ner_tf_inference.ipynb) |
| [TransformerXL](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/LanguageModeling/Transformer-XL) | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                         | -   | -                                                                                                                                           |
| [GNMT](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Translation/GNMT)                         | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                         | -   | -                                                                                                                                           |
| [Faster Transformer](https://github.com/NVIDIA/DeepLearningExamples/tree/master/FasterTransformer)                     | Tensorflow  | -    | -   | -         | -          | Yes | -    | -                                                                                                         | -   | -                                                                                                                                           |

### Recommender Systems

| Models                                                                                                         | Framework   | A100 | AMP | Multi-GPU | Multi-Node | TRT | ONNX | Triton                                                                                               | DLC | NB                                                                                                      |
| -------------------------------------------------------------------------------------------------------------- | ----------- | ---- | --- | --------- | ---------- | --- | ---- | ---------------------------------------------------------------------------------------------------- | --- | ------------------------------------------------------------------------------------------------------- |
| [DLRM](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Recommendation/DLRM)                 | PyTorch     | Yes  | Yes | Yes       | -          | -   | Yes  | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Recommendation/DLRM/triton) | Yes | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Recommendation/DLRM/notebooks) |
| [DLRM](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/Recommendation/DLRM)             | TensorFlow2 | Yes  | Yes | Yes       | Yes        | -   | -    | -                                                                                                    | Yes | -                                                                                                       |
| [NCF](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/Recommendation/NCF)                   | PyTorch     | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                    | -   | -                                                                                                       |
| [Wide&Deep](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Recommendation/WideAndDeep)  | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                    | Yes | -                                                                                                       |
| [Wide&Deep](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow2/Recommendation/WideAndDeep) | TensorFlow2 | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                    | Yes | -                                                                                                       |
| [NCF](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Recommendation/NCF)                | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                    | Yes | -                                                                                                       |
| [VAE-CF](https://github.com/NVIDIA/DeepLearningExamples/tree/master/TensorFlow/Recommendation/VAE-CF)          | TensorFlow  | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                    | -   | -                                                                                                       |

### Speech to Text

| Models                                                                                                    | Framework | A100 | AMP | Multi-GPU | Multi-Node | TRT | ONNX | Triton                                                                                                   | DLC | NB                                                                                                           |
| --------------------------------------------------------------------------------------------------------- | --------- | ---- | --- | --------- | ---------- | --- | ---- | -------------------------------------------------------------------------------------------------------- | --- | ------------------------------------------------------------------------------------------------------------ |
| [Jasper](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/SpeechRecognition/Jasper)     | PyTorch   | Yes  | Yes | Yes       | -          | Yes | Yes  | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/SpeechRecognition/Jasper/trtis) | Yes | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/SpeechRecognition/Jasper/notebooks) |
| [Hidden Markov Model](https://github.com/NVIDIA/DeepLearningExamples/tree/master/Kaldi/SpeechRecognition) | Kaldi     | -    | -   | Yes       | -          | -   | -    | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/Kaldi/SpeechRecognition)                | -   | -                                                                                                            |

### Text to Speech

| Models                                                                                                                  | Framework | A100 | AMP | Multi-GPU | Multi-Node | TRT | ONNX | Triton                                                                                                        | DLC | NB  |
| ----------------------------------------------------------------------------------------------------------------------- | --------- | ---- | --- | --------- | ---------- | --- | ---- | ------------------------------------------------------------------------------------------------------------- | --- | --- |
| [FastPitch](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/SpeechSynthesis/FastPitch)               | PyTorch   | Yes  | Yes | Yes       | -          | -   | -    | -                                                                                                             | Yes | -   |
| [FastSpeech](https://github.com/NVIDIA/DeepLearningExamples/tree/master/CUDA-Optimized/FastSpeech)                      | PyTorch   | -    | Yes | Yes       | -          | Yes | -    | -                                                                                                             | -   | -   |
| [Tacotron 2 and WaveGlow](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/SpeechSynthesis/Tacotron2) | PyTorch   | Yes  | Yes | Yes       | -          | Yes | Yes  | [Yes](https://github.com/NVIDIA/DeepLearningExamples/tree/master/PyTorch/SpeechSynthesis/Tacotron2/trtis_cpp) | Yes | -   |

### Graph Neural Networks

| Models                                                                                                                  | Framework | A100 | AMP | Multi-GPU | Multi-Node | TRT | ONNX | Triton | DLC | NB  |
| ----------------------------------------------------------------------------------------------------------------------- | --------- | ---- | --- | --------- | ---------- | --- | ---- | ------ | --- | --- |
| [SE(3)-Transformer](https://github.com/NVIDIA/DeepLearningExamples/tree/master/DGLPyTorch/DrugDiscovery/SE3Transformer) | PyTorch   | Yes  | Yes | Yes       | -          | -   | -    | -      | -   | -   |
