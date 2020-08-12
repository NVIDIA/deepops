import kfp
import kfp_server_api
import json
import time

# Define and build a Kubeflow Pipeline
@kfp.dsl.pipeline(
    name="kubeflow-quick-test",
    description="Verify Kubeflow can launch a container via a pipeline")
def test_kubeflow_op():
    op = kfp.dsl.ContainerOp(
      name='kubeflow-test-op',
      image='nvcr.io/nvidia/rapidsai/rapidsai:cuda10.1-runtime-centos7',
      command=["/bin/bash", "-cx"],
      arguments=["echo 'Container started!'"],
      file_outputs={}
      )                 
kfp.compiler.Compiler().compile(test_kubeflow_op, 'kubeflow-test.yml')

# Connect to Kubeflow and create job, this simply rungs RAPIDS and prints out a message                 
while True:
    try:
        print("Submitting Kubeflow pipeline")
        run_result = kfp.Client(host=None).create_run_from_pipeline_package('kubeflow-test.yml', arguments={})
        break # This means it worked!
    except kfp_server_api.rest.ApiException as e:
        print("Hit an error, waiting and trying again: {}".format(e))
        time.sleep(30) # Occassionally Kubeflow fails to respond even when all deployments are up. I don't know why, sometimes it is a 403, sometimes a 500, and sometimes it works. So we will just wait and re-try until the test/script times out.

for i in range(70): # The test .sh times out after 600 seconds. So we run a little longer than that. This accounts mostly for NGC download time.
    print("Polling for pipeline status: {} - {}".format(run_result, i))
    status = kfp.Client(host=None).get_run(run_result.run_id).run.status
    if status == "Succeeded":
        print("SUCCESS: Kubeflow launched a container successfully")
        break
    print("Got {}, waiting some more...".format(status))
    time.sleep(10) # Wait 10 seconds and poll
