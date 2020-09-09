#!/usr/bin/env python3
import kfp.dsl as dsl
from kubernetes import client as k8s_client
import yaml


__TRTIS_CONTAINER_VERSION__ = 'nvcr.io/nvidia/tensorrtserver:20.02-py3'
__TRTIS_POD_LABEL__ = 'trtis-kubeflow'
__TRTIS_SERVICE_MANIFEST___ = '''
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
    - name: grpc
      port: 8001
      targetPort: 8001
    - name: metrics
      port: 8002
      targetPort: 8002
'''.format(__TRTIS_POD_LABEL__, __TRTIS_POD_LABEL__)


class ObjectDict(dict):
  def __getattr__(self, name):
    if name in self:
      return self[name]
    else:
      raise AttributeError("No such attribute: " + name)


class TrtisDeploy(dsl.ContainerOp):
  '''Deploy TRTIS'''
  def __init__(self, name, models):
    cmd = ["/bin/bash", "-cx"]
    arguments = ["echo Deploying: " + str(models) + "TODO;ls /data; ls /results; ls /checkpoints; trtserver --model-store=" + models]

    super(TrtisDeploy, self).__init__(
      name=name,
      image=__TRTIS_CONTAINER_VERSION__,
      command=cmd,
      arguments=arguments,
      file_outputs={}
      )

    self.pod_labels['app'] = __TRTIS_POD_LABEL__
    name=name


class TrtisService(dsl.ResourceOp):
  '''Launch TRTIS Service'''
  def __init__(self, name):

    super(TrtisService, self).__init__(
      name=name,
      k8s_resource=yaml.load(__TRTIS_SERVICE_MANIFEST___),
      action='create'
)
