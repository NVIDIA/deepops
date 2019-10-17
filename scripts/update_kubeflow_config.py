#!/usr/bin/env python
'''Because there is currently no clean way to update this config through ks this script exists.

The purpose of this script is to dynamically update Kubeflow to point at the latest NGC containers.
In addition to that it changes default resource requests to optimize for GPUs

TODO: Do this with Ansible
'''


#import requests
import json
import urllib2
import logging
import yaml
import os


NVCR = 'nvcr.io'

try:
    KUBEFLOW_SRC = os.environ['KUBEFLOW_SRC']
    KSAPP_DIR = os.environ['KSAPP_DIR']
except OSError as e:
    logging.error("Could not locate KSAPP_DIR or KUBEFLOW_SRC: {}".format(e))
    exit()



def get_images(url='https://api.ngc.nvidia.com/v2/repos', number_tags=5):
    images = []

    # Get response from Registry
    try:
        req = urllib2.Request(url)
        repos = urllib2.urlopen(req)
    except Exception as e:
        logging.error("Failed to get repos {}".format(e)) # Fail on non-200 status code or other issues
        return 1

    # Parse Registry response
    try:
        repos = json.loads(repos.read())
    except Exception as e:
        logging.error("Failed to parse NGC response")
        return 1
    if 'repositories' not in repos:
        loggging.warn("no repositories listed")
        return 1

    # Iterate through registry response
    for repo in repos['repositories']:
        if 'tags' not in repo or \
            'namespace' not in repo or \
            'name' not in repo:
            continue
        count = 0
        for tag in repo['tags']:
            images.append((repo['namespace'], repo['name'],tag))
            count += 1
            if count >= number_tags:
                break
    return map(lambda x : "{}/{}/{}:{}".format(NVCR, x[0], x[1], x[2]), images)


def update_yaml(images, yaml_file, str1):
    # Update file to be valide YAML before parsing it
    str2 = 'value: RREPLACE_ME'
    with open(yaml_file, 'r') as fname:
        config = yaml.load(fname.read().replace(str1, str2), Loader=yaml.FullLoader)

    # Update YAML file
    try:
        # TODO: This isn't rendering the rest of the page properly
        # config['spawnerFormDefaults']['extraResources']['value'] = '"{{\\\"nvidia.com/gpu\\\": 1}}"'
        config['spawnerFormDefaults']['image']['value'] = images[0]
        config['spawnerFormDefaults']['image']['options'] = images # TODO: Potentially only show 1-3 tags for each image
    except KeyError:
        logging.error("Couldn't parse config for update")
        return

    # Write out YAML file back to how Kubeflow expects
    config = yaml.dump(config, default_flow_style=False).replace(str2, str1)
    # TODO: "fix for": This isn't rendering the rest of the page properly
    if True:
        config = config.replace('\'{{}}\'', '"{{}}"')

    with open(yaml_file, 'w') as fname:
        fname.write(config)


if __name__ == '__main__':
    images = get_images()
    # This block of code updates the source files used for new ks apps
    try:
        update_yaml(images,
            '{}/kubeflow/jupyter/config.yaml'.format(KUBEFLOW_SRC),
            'value: {username}-workspace')
        update_yaml(images,
            '{}/kubeflow/jupyter/ui/rok/config.yaml'.format(KUBEFLOW_SRC),
            'value: {username}{servername}-workspace')
        update_yaml(images,
            '{}/kubeflow/jupyter/ui/default/config.yaml'.format(KUBEFLOW_SRC),
            'value: {username}{servername}-workspace')
        logging.info("Updated KS source code configurations.")
    except IOError as e: # the ks_app files may not exist at time of running this
        logging.error("Failed to update KS source code configurations: {}".format(e))

    # This updates KS apps
    try:
        update_yaml(images,
            '{}/vendor/kubeflow/jupyter/config.yaml'.format(KSAPP_DIR),
            'value: {username}-workspace')
        update_yaml(images,
            '{}/vendor/kubeflow/jupyter/ui/rok/config.yaml'.format(KSAPP_DIR),
            'value: {username}{servername}-workspace')
        update_yaml(images,
            '{}/vendor/kubeflow/jupyter/ui/default/config.yaml'.format(KSAPP_DIR),
            'value: {username}{servername}-workspace')
        logging.info("Updated KS app configurations.")
    except IOError as e: # the ks_app files may not exist at time of running this
        logging.error("Failed to update KS app configurations: {}".format(e))

