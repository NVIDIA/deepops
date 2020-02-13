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
    KF_DIR = os.environ['KF_DIR']
except OSError as e:
    logging.error("Could not locate KF_DIR: {}".format(e))
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


def update_yaml(images, yaml_file):
    with open(yaml_file, 'r') as fname:
        config = yaml.load(fname.read(), Loader=yaml.FullLoader)
    ui_config = yaml.load(config['data']['spawner_ui_config.yaml'], Loader=yaml.FullLoader)

    # XXX: the yaml file doesn't read in properly due to the line 'spawner_ui_config.yaml: |'. So we pull it out and put it back later.
    config['data']['spawner_ui_config.yaml'] = ui_config

    # Update YAML file with NVIDIA default config and first 3 tags of all NGC containers
    try:
        config['data']['spawner_ui_config.yaml']['spawnerFormDefaults']['extraResources']['value'] = '{"nvidia.com/gpu": 1}'
        config['data']['spawner_ui_config.yaml']['spawnerFormDefaults']['image']['value'] = images[0]
        config['data']['spawner_ui_config.yaml']['spawnerFormDefaults']['image']['options'] = images
    except KeyError:
        logging.error("Couldn't parse config for update")
        return

    with open(yaml_file, 'w') as fname:
        # When Python reads the Kubeflow YAML in it is having difficulty parsing the | and then removes some quotes. We put it back here.
        yaml_string = yaml.dump(config).replace('spawner_ui_config.yaml:', 'spawner_ui_config.yaml: |')
        yaml_string = yaml_string.replace("workspace-{notebook-name}", "'workspace-{notebook-name}'")
        fname.write(yaml_string)


if __name__ == '__main__':
    images = get_images()
    # This block of code updates kustomize files, in order for them to take effect you must run kfctl apply
    try:
        update_yaml(images,
            '{}/kustomize/jupyter-web-app/base/config-map.yaml'.format(KF_DIR))
        logging.info("Updated KS kustomize code configurations.")
    except IOError as e: # the ks_app files may not exist at time of running this
        logging.error("Failed to update KS kustomize code configurations: {}".format(e))
