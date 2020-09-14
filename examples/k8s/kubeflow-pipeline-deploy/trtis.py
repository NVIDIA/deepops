#!/usr/bin/env python3
'''
Kubeflow documentation: https://kubeflow-pipelines.readthedocs.io/en/latest/_modules/kfp/dsl/_container_op.html
K8S documentation: https://github.com/kubernetes-client/python/blob/02ef5be4ecead787961037b236ae498944040b43/kubernetes/docs/V1Container.md

Example TensorRT Inference Server Models: https://docs.nvidia.com/deeplearning/sdk/tensorrt-inference-server-master-branch-guide/docs/run.html#example-model-repository
Example TensorRT Inference Server Client: https://docs.nvidia.com/deeplearning/sdk/tensorrt-inference-server-master-branch-guide/docs/client_example.html#section-getting-the-client-examples
Bugs:
  Cannot dynamically assign GPU counts: https://github.com/kubeflow/pipelines/issues/1956

# Manual run example:
nvidia-docker run --rm --shm-size=1g --ulimit memlock=-1 --ulimit stack=67108864 -p8000:8000 -p8001:8001 -p8002:8002 -v/raid/shared/results/models/:/models nvcr.io/nvidia/tensorrtserver:20.02-py3 trtserver --model-repository=/models
docker run -it --rm --net=host tensorrtserver_client /workspace/install/bin/image_client -m resnet50_netdef images/mug.jpg
'''
import trtis_ops
import kfp.dsl as dsl
from kubernetes import client as k8s_client


@dsl.pipeline(
    name='trtisPipeline',
    description='Deploy a TRTIS server'
)


def trtis_pipeline(nfs_server, nfs_export_path, models_dir_path):

    op_dict = {}

    # NFS information
    nfs_export = str(nfs_export_path)
    nfs_data_export = "{}/data".format(nfs_export) # Mount point on NFS
    nfs_results_export = "{}/results".format(nfs_export) # Mount point on NFS
    nfs_checkpoints_export = "{}/checkpoints".format(nfs_export) # Mount point on NFS
    # nfs_server = "nfs-server-01"

    # Hardcoded paths mounted in the TRTIS container
    results_dir = "/results/"
    data_dir = "/data/"
    checkpoints_dir = "/checkpoints/"
    models = "/results/{}".format(models_dir_path)

    # Common Operations
    op_dict['trtis_service'] = trtis_ops.TrtisService('trtis_service')
    op_dict['trtis_deploy'] = trtis_ops.TrtisDeploy('trtis_deploy', models)

    # Use GPUs
    op_dict['trtis_deploy'].set_gpu_limit(1, vendor = "nvidia")

    # Add TRTIS Ports
    op_dict['trtis_deploy'].add_port(k8s_client.V1ContainerPort(container_port=8000, host_port=8000)) # HTTP
    op_dict['trtis_deploy'].add_port(k8s_client.V1ContainerPort(8001)) # gRPC
    op_dict['trtis_deploy'].add_port(k8s_client.V1ContainerPort(8002)) # Metrics
    
    # Mount Volumes
    for name, container_op in op_dict.items():
        if name == 'trtis_service':
            continue
        container_op.add_volume(k8s_client.V1Volume(nfs=k8s_client.V1NFSVolumeSource(
            path=nfs_data_export, server=nfs_server,
            read_only=True),
            name=name.replace("_","-")+"-data"))
        container_op.add_volume_mount(k8s_client.V1VolumeMount(
            mount_path=data_dir,
            name=name.replace("_","-")+"-data",
            read_only=True))
        container_op.add_volume(k8s_client.V1Volume(nfs=k8s_client.V1NFSVolumeSource(
            path=nfs_results_export, server=nfs_server,
            read_only=True),
            name=name.replace("_","-")+"-results"))
        container_op.add_volume_mount(k8s_client.V1VolumeMount(
            mount_path=results_dir,
            name=name.replace("_","-")+"-results"))
        container_op.add_volume(k8s_client.V1Volume(nfs=k8s_client.V1NFSVolumeSource(
            path=nfs_checkpoints_export, server=nfs_server,
            read_only=True),
            name=name.replace("_","-")+"-checkpoints"))
        container_op.add_volume_mount(k8s_client.V1VolumeMount(
            mount_path=checkpoints_dir,
            name=name.replace("_","-")+"-checkpoints"))

    '''
    TODO Implement https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/V1Probe.md:
            livenessProbe:
                httpGet:
                path: /api/health/live
                port: http
            readinessProbe:
                initialDelaySeconds: 5
                periodSeconds: 5
                httpGet:
                path: /api/health/ready
                port: http
    '''

if __name__ == '__main__':
    import kfp.compiler as compiler
    compiler.Compiler().compile(trtis_pipeline, __file__ + '.tar.gz')
