#!/usr/bin/env python3
import kfp.dsl as dsl
from kubernetes import client as k8s_client
import yaml


__TRITON_CONTAINER_VERSION__ = 'nvcr.io/nvidia/tritonserver:21.02-py3'
__TRITON_POD_LABEL__ = 'triton-kubeflow'
__TRITON_SERVICE_MANIFEST___ = '''
apiVersion: v1
kind: Service
metadata:
  name: {}
spec:
  selector:
    app: {}
  ports:
    - name: http
      protocol: TCP
      port: 8000
      targetPort: 8000
      nodePort: 30800
    - name: grpc
      port: 8001
      targetPort: 8001
      nodePort: 30801
    - name: metrics
      port: 8002
      targetPort: 8002
      nodePort: 30802
  type: NodePort
'''.format(__TRITON_POD_LABEL__, __TRITON_POD_LABEL__)


class ObjectDict(dict):
  def __getattr__(self, name):
    if name in self:
      return self[name]
    else:
      raise AttributeError("No such attribute: " + name)


class TritonVolume(dsl.ResourceOp):
  '''Initialize a  volume if one does not exist'''
  def __init__(self, name, pv_name):
    super(TritonVolume, self).__init__(
      k8s_resource=k8s_client.V1PersistentVolumeClaim(
      api_version="v1", kind="PersistentVolumeClaim",
      metadata=k8s_client.V1ObjectMeta(name=pv_name),
      spec=k8s_client.V1PersistentVolumeClaimSpec(
          access_modes=['ReadWriteMany'], resources=k8s_client.V1ResourceRequirements(
              requests={'storage': '2000Gi'}),
          storage_class_name="nfs-client")),
      action='apply',
      name=name
      )
    name=name


class TritonDownload(dsl.ContainerOp):
  '''Download example Triton models and move them into the PV'''
  def __init__(self, name, models):
    cmd = ["/bin/bash", "-cx"]
    arguments = ["cd /tmp; git clone https://github.com/triton-inference-server/server.git; " \
                "cd server/docs/examples; ./fetch_models.sh; cd model_repository; cp -a . " + str(models)]

    super(TritonDownload, self).__init__(
      name=name,
      image=__TRITON_CONTAINER_VERSION__,
      command=cmd,
      arguments=arguments,
      file_outputs={}
      )

    self.pod_labels['app'] = __TRITON_POD_LABEL__
    name=name


class TritonDeploy(dsl.ContainerOp):
  '''Deploy Triton'''
  def __init__(self, name, models):
    cmd = ["/bin/bash", "-cx"]
    arguments = ["echo Deploying: " + str(models) + ";ls /data; ls /results; ls /checkpoints; tritonserver --model-store=" + models]

    super(TritonDeploy, self).__init__(
      name=name,
      image=__TRITON_CONTAINER_VERSION__,
      command=cmd,
      arguments=arguments,
      file_outputs={}
      )

    self.pod_labels['app'] = __TRITON_POD_LABEL__
    name=name


class TritonService(dsl.ResourceOp):
  '''Launch Triton Service'''
  def __init__(self, name):

    super(TritonService, self).__init__(
      name=name,
      k8s_resource=yaml.load(__TRITON_SERVICE_MANIFEST___),
      action='create'
)
