#!/usr/bin/env python3
'''
Kubeflow documentation: https://kubeflow-pipelines.readthedocs.io/en/latest/_modules/kfp/dsl/_container_op.html
K8S documentation: https://github.com/kubernetes-client/python/blob/02ef5be4ecead787961037b236ae498944040b43/kubernetes/docs/V1Container.md

Example Triton Inference Server Models: https://docs.nvidia.com/deeplearning/sdk/tensorrt-inference-server-master-branch-guide/docs/run.html#example-model-repository
Example Triton Inference Server Client: https://docs.nvidia.com/deeplearning/sdk/tensorrt-inference-server-master-branch-guide/docs/client_example.html#section-getting-the-client-examples
Bugs:
  Cannot dynamically assign GPU counts: https://github.com/kubeflow/pipelines/issues/1956

# Manual run example:
nvidia-docker run --rm --shm-size=1g --ulimit memlock=-1 --ulimit stack=67108864 -p8000:8000 -p8001:8001 -p8002:8002 -v/raid/shared/results/model_repository/:/model_repository nvcr.io/nvidia/tensorrtserver:20.02-py3 trtserver --model-repository=/model_repository
docker run -it --rm --net=host tensorrtserver_client /workspace/install/bin/image_client -m resnet50_netdef images/mug.jpg
'''
import triton_ops
import kfp.dsl as dsl
from kubernetes import client as k8s_client


@dsl.pipeline(
    name='tritonPipeline',
    description='Deploy a Triton server'
)


def triton_pipeline(skip_examples):

    op_dict = {}

    # Hardcoded paths mounted in the Triton container
    results_dir = "/results/"
    data_dir = "/data/"
    checkpoints_dir = "/checkpoints/"
    models = "/results/model_repository"

    # Set default volume names
    pv_data = "triton-data"
    pv_results = "triton-results"
    pv_checkpoints = "triton-checkpoints"

    # Create K8s PVs
    op_dict['triton_volume_results'] = triton_ops.TritonVolume('triton_volume_results', pv_results)
    op_dict['triton_volume_data'] = triton_ops.TritonVolume('triton_volume_data', pv_data)
    op_dict['triton_volume_checkpoints'] = triton_ops.TritonVolume('triton_volume_checkpoints', pv_checkpoints)

    # Download example models
    with dsl.Condition(skip_examples == '', name='skip-examples-download'):
        op_dict['triton_download'] = triton_ops.TritonDownload('triton_download', models)

    # Common Operations
    op_dict['triton_service'] = triton_ops.TritonService('triton_service')
    op_dict['triton_deploy'] = triton_ops.TritonDeploy('triton_deploy', models)

    # Use GPUs
    op_dict['triton_deploy'].set_gpu_limit(1, vendor = "nvidia")

    # Add Triton Ports
    op_dict['triton_deploy'].add_port(k8s_client.V1ContainerPort(container_port=8000, host_port=8000)) # HTTP
    op_dict['triton_deploy'].add_port(k8s_client.V1ContainerPort(8001, host_port=8001)) # gRPC
    op_dict['triton_deploy'].add_port(k8s_client.V1ContainerPort(8002, host_port=8002)) # Metrics

    # Set order so tha volumes are created, then examples downloaded, then service started
    op_dict['triton_download'].after(op_dict['triton_volume_results'])
    op_dict['triton_download'].after(op_dict['triton_volume_data'])
    op_dict['triton_download'].after(op_dict['triton_volume_checkpoints'])
    op_dict['triton_deploy'].after(op_dict['triton_download'])

    # Mount Volumes
    for name, container_op in op_dict.items():
        if name == 'triton_service' or type(container_op) == triton_ops.TritonVolume:
            continue

        container_op.add_volume(k8s_client.V1Volume(persistent_volume_claim=k8s_client.V1PersistentVolumeClaimVolumeSource(
            claim_name=pv_results, read_only=False), name=pv_results))
        container_op.add_volume_mount(k8s_client.V1VolumeMount(
            mount_path=results_dir, name=pv_results, read_only=False))

        container_op.add_volume(k8s_client.V1Volume(persistent_volume_claim=k8s_client.V1PersistentVolumeClaimVolumeSource(
            claim_name=pv_data, read_only=False), name=pv_data))
        container_op.add_volume_mount(k8s_client.V1VolumeMount(
            mount_path=data_dir, name=pv_data, read_only=True))

        container_op.add_volume(k8s_client.V1Volume(persistent_volume_claim=k8s_client.V1PersistentVolumeClaimVolumeSource(
            claim_name=pv_checkpoints, read_only=False), name=pv_checkpoints))
        container_op.add_volume_mount(k8s_client.V1VolumeMount(
            mount_path=checkpoints_dir, name=pv_checkpoints, read_only=True))

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
    compiler.Compiler().compile(triton_pipeline, __file__ + '.tar.gz')
