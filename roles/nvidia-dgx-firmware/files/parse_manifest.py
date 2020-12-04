#!/usr/bin/python

import json

from collections import OrderedDict
from sys import argv


def return_json(payload):
    return(json.dumps(payload,
                      sort_keys=True,
                      indent=4
                      )
           )


if argv[1] == 'update_order':

    fw_manifest = argv[2]
    ver_manifest = argv[3]

    updateItems = {}
    updateOrder = OrderedDict()

    with open(fw_manifest) as f:
        manifest_jsonify = json.load(f)

    with open(ver_manifest) as f:
        version_jsonify = json.load(f)

    # Grab sequence type info from FW Manifest..
    for obj in manifest_jsonify:
        try:
            for component in manifest_jsonify[obj]['Items']:
                updateItems[component['CompName']] = \
                    [
                        component['Sequence'],
                        component['CompModel'],
                        obj
                    ]

        except KeyError as e:
            pass

    # Iterate through FW Versioning, write Update Condition to updateItems
    for item in version_jsonify:
        for component in version_jsonify[item]['Items']:
            if not component['IsUpToDate']:
                try:
                    updateItems[component['ID']].append({'NeedsUpdate': True})
                except:
                    try:
                        updateItems[component['Model']].append({'NeedsUpdate': True})
                    except:
                        continue

            if component['IsUpToDate']:
                try:
                    updateItems[component['ID']].append({'NeedsUpdate': False})
                except:
                    try:
                        updateItems[component['Model']].append({'NeedsUpdate': False})
                    except:
                        continue

    for i in updateItems:
        try:
            needsUpdate = updateItems[i][3]
            pass

        except IndexError:
            group = updateItems[i][2]

            for item in version_jsonify[group]['Items']:
                if not item['IsUpToDate']:
                    updateItems[i].append({'NeedsUpdate': True})

                    break

                if item['IsUpToDate']:
                    updateItems[i].append({'NeedsUpdate': False})

                    continue

    for k in updateItems:
        updateItems[k] = [i for n, i in enumerate(updateItems[k]) if i not in updateItems[k][n + 1:]]

    sortedUpdateItems = sorted(updateItems.items(), key=lambda x: x[1][0])

    try:
        if argv[4] == 'order_length':
            count = 0
            for i in sortedUpdateItems:
                if i[1][3]['NeedsUpdate']:
                    count += 1

            print(count - 1)
            exit(0)

    except IndexError:
        pass

    itemsToUpdate = OrderedDict()

    for i in sortedUpdateItems:
        if i[1][3]['NeedsUpdate']:
            if i[0] == 'MB_CEC':
                itemsToUpdate[(str(i[0]))] = True
            elif i[0] == 'Delta_CEC':
                itemsToUpdate[(str(i[0]))] = True
            else:
                itemsToUpdate[str(i[1][2])] = True

    for item in itemsToUpdate:
        print(item)

    exit(0)

if argv[1] == 'parse_update_json':
    file_path = argv[2]

    fw_update_json = {
        'Error': True,
        'State': 'Unknown',
        'Action': 'Check Output Log'
    }

    with open(file_path) as f:
        fw_update = f.readlines()

    for line in fw_update:
        try:
            lineJson = json.loads(line)

            if 'FirmwareLoadAction' in json.loads(line).keys(): # Detects if chassis-level power cycle is required
                fw_update_json = json.loads(line)
            if 'Reboot required' in lineJson['Message']: # Detects if host-level reboot is required
                fw_update_json['RebootRequired'] = True

            if lineJson['State'] == 'Failed':
                fw_update_json['State'] = 'Failed'
                fw_update_json['Message'] = lineJson['Message']
                break

            if lineJson['State'] == 'Canceled':
                fw_update_json['State'] = 'Canceled'
                fw_update_json['Message'] = lineJson['Message']
                break

            if lineJson['State'] == 'Done':
                fw_update_json['State'] = 'Done'
                fw_update_json['Message'] = lineJson['Message']

        except Exception as e:
            continue

    print(return_json(fw_update_json))


if argv[1] == 'parse_versioning':
    file_path = argv[2]

    manifest_json = {
        'ErrorWritingVersioning': True
    }

    with open(file_path) as f:
        output_all = f.readlines()

    # Grab JSON from raw output
    for line in output_all:
        try:
            manifest_json = json.loads(line)
        except ValueError:
            pass
    try:
        if manifest_json['ErrorWritingVersioning']:
            print('No JSON could be loaded, is the container already running?')
            exit(1)

    except KeyError:
        print(json.dumps(manifest_json,
                         sort_keys=True,
                         indent=4
                         )
              )
