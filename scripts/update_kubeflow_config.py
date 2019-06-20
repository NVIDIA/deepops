#!/usr/bin/env python
'''Because there is currently no clean way to update this config through ks this script exists.

The purpose of this script is to dynamically update Kubeflow to point at the latest NGC containers.
In addition to that it changes default resource requests to optimize for GPUs
'''


#import requests
import json
import urllib2
import logging
import yaml


def get_images(url='https://api.ngc.nvidia.com/v2/repos'):
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
        if 'tags' not in repo or 'name' not in repo:
            continue
        for tag in repo['tags']:
            images.append((repo['name'],tag))
    return map(lambda x : "nvcr.io/nvidia/{}:{}".format(x[0], x[1]), images) #  TODO: Remove url hardcoding


def update_yaml(images, yaml_file='/opt/kubeflow/kubeflow/jupyter/ui/default/config.yaml'):
    # Update file to be valide YAML before parsing it
    str1 = 'value: {username}{servername}-workspace'
    str2 = 'REPLACE_ME'
    with open(yaml_file, 'r') as fname:
        config = yaml.load(fname.read().replace(str1, str2))

    # Update YAML file
    try:
        config['spawnerFormDefaults']['extraResources']['value'] = '"{{\\\"nvidia.com/gpu\\\": 1}}"'
        config['spawnerFormDefaults']['image']['value'] = images[0]
        config['spawnerFormDefaults']['image']['options'] = images # TODO: Potentially only show 1-3 tags for each image
    except KeyError:
        print("Couldn't parse config for update")
        return

    # Write out YAML file back to how Kubeflow expects
    config = yaml.dump(config, default_flow_style=False).replace(str2, str1)
    with open(yaml_file, 'w') as fname:
        fname.write(config)


if __name__ == '__main__':
    images = get_images()
    update_yaml(images) # TODO: Allow user to change file name
