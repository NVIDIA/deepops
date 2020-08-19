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
      image='busybox',
      command=["/bin/sh", "-cx"],
      arguments=["echo 'Container started!'"],
      file_outputs={}
      )                 
kfp.compiler.Compiler().compile(test_kubeflow_op, 'kubeflow-test.yml')

# Connect to Kubeflow and create job, this simply rungs RAPIDS and prints out a message                 
while True:
    time.sleep(30) # Occassionally Kubeflow fails to respond even when all deployments are up. I don't know why, sometimes it is a 403, sometimes a 500, and sometimes it works. So we will just wait and re-try until the test/script times out.
    try:
        print("Submitting Kubeflow pipeline")
        run_result = kfp.Client(host=None).create_run_from_pipeline_package('kubeflow-test.yml', arguments={})
        break # This means it worked!
    except kfp_server_api.rest.ApiException as e:
        print("Hit an error, waiting and trying again: {}".format(e))

for i in range(70): # The test eventually times out. So we run a little longer than that. This accounts mostly for NGC download time.
    print("Polling for pipeline status: {} - {}".format(run_result, i))
    run = kfp.Client(host=None).get_run(run_result.run_id).run
    if run.status == "Succeeded":
        print("SUCCESS: Kubeflow launched a container successfully")
        break
    print("Got {}, waiting some more... {}".format(run.status, run))
    time.sleep(10) # Wait 10 seconds and poll
