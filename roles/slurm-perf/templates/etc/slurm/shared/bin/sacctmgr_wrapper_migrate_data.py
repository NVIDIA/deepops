#!/usr/bin/env python3

import argparse
import collections
import json
import logging
import os
import subprocess


logging.basicConfig(level=os.environ.get('LOGLEVEL', 'WARNING'))
logger = logging.getLogger(__name__)

ENTITY_ID_FIELDS = collections.OrderedDict([
    ('cluster', ['cluster']),
    ('account', ['account']),
    ('qos', ['name']),
    ('association', ['cluster', 'account', 'user']),
    ('user', ['user']),
])

ENTITY_TYPE_MAP = {
    'cluster': 'cluster',
    'account': 'account',
    'qos': 'qos',
    'association': 'user',  # XXX `sacctmgr create association` does not work
    'user': 'user',
}

ENTITY_DEFAULTS = {
    'user': {'admin': 'None'},
}


def parse_input(filename):
    with open(filename) as infile:
        orig_data = json.load(infile)
    assert isinstance(orig_data, dict)

    cleaned_data = collections.defaultdict(list)
    for entity_type in orig_data:
        entities = orig_data[entity_type]
        assert isinstance(entities, list)
        for orig_entity in entities:
            assert isinstance(orig_entity, dict)
            entity = ENTITY_DEFAULTS.get(entity_type, {}).copy()
            entity.update(orig_entity)

            if entity_type == 'association' and 'qos' in entity:
                entity['qos'] = ','.join(sorted(entity['qos'].split(',')))  # sort qos

            cleaned_data[entity_type].append(entity)

    return cleaned_data


def entity_repr(entity_type, entity_spec):
    return '{:s}({:s})'.format(
        entity_type,
        ','.join([
            '{:s}={:s}'.format(k, entity_spec[k])
            for k in ENTITY_ID_FIELDS[entity_type]
        ]),
    )


def run_cmd(args):
    logger.debug('COMMAND: {:s}'.format(' '.join(args)))
    result = subprocess.run(args, check=True, encoding='utf-8',
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    logger.debug('RESULT: {:s}'.format(result.stdout.strip()))
    return result


def entity_exists(entity_type, entity_spec):
    args = ['sacctmgr', 'show', '-P', ENTITY_TYPE_MAP[entity_type], 'where']
    for id_field in ENTITY_ID_FIELDS[entity_type]:
        args.append('{:s}={:s}'.format(id_field, entity_spec[id_field]))
    if entity_type == 'association':
        args.append('withassoc')
    result = run_cmd(args)

    stdout_lines = result.stdout.strip().split('\n')
    if len(stdout_lines) == 2:
        if entity_type != 'association':
            return True

        # XXX `sacctmgr show user withassoc user=X account=Y` returns data
        #   even if the association does not exist
        existing_spec = dict(zip(
            [k.strip().lower() for k in stdout_lines[0].strip().split('|')],
            [v.strip() for v in stdout_lines[1].strip().split('|')],
        ))
        return existing_spec['account'] != ''
    elif len(stdout_lines) == 1:
        return False
    else:
        raise ValueError('Found multiple entities for {:s}'.format(
            entity_repr(entity_type, entity_spec)))


def create_entity(entity_type, entity_spec):
    args = ['sacctmgr', 'create', '-i', ENTITY_TYPE_MAP[entity_type]]
    for k, v in entity_spec.items():
        args.append('{:s}={:s}'.format(k, v))
    run_cmd(args)


# XXX `sacctmgr show account format=parent` does not work
# even though you can do `sacctmgr create account parent=foo`
def get_account_parent(account):
    args = ['sacctmgr', 'show', '-P', '--noheader', 'association',
            'account={:s}'.format(account), 'user=', 'format=parentname']
    result = run_cmd(args)

    stdout_lines = result.stdout.strip().split('\n')
    if len(stdout_lines) == 1:
        return stdout_lines[0]
    else:
        raise ValueError('Failed to get parent account for account={:s}'.format(account))


def entity_needs_modify(entity_type, entity_spec):
    format_keys = []
    for k in entity_spec.keys():
        if entity_type == 'account' and k == 'parent':
            pass
        else:
            format_keys.append(k)

    args = [
        'sacctmgr', 'show', '-P', ENTITY_TYPE_MAP[entity_type],
        'format={:s}'.format(','.join(format_keys)),
        'where',
    ]
    for id_field in ENTITY_ID_FIELDS[entity_type]:
        args.append('{:s}={:s}'.format(id_field, entity_spec[id_field]))
    if entity_type == 'association':
        args.append('withassoc')

    result = run_cmd(args)

    stdout_lines = result.stdout.strip().split('\n')
    if len(stdout_lines) > 2:
        raise ValueError('Found multiple entities for {:s}'.format(
            entity_repr(entity_type, entity_spec)))
    elif len(stdout_lines) == 1:
        raise RuntimeError('Called entity_needs_modify() for {:s}, but it does not exist'.format(
            entity_repr(entity_type, entity_spec)))

    keys = [k.strip().lower() for k in stdout_lines[0].strip().split('|')]
    values = [v.strip() for v in stdout_lines[1].strip().split('|')]

    if entity_type == 'account':
        # XXX input is "description" but output is "descr"
        keys = [k if k != 'descr' else 'description' for k in keys]

    if entity_type == 'user':
        # XXX input is "defaultaccount" but output is "def acct"
        keys = [k if k != 'def acct' else 'defaultaccount' for k in keys]

    if entity_type == 'association':
        # XXX input is "defaultqos" but output is "def qos"
        keys = [k if k != 'def qos' else 'defaultqos' for k in keys]

    existing_spec = dict(zip(keys, values))

    if entity_type == 'account' and 'parent' in entity_spec:
        existing_spec['parent'] = get_account_parent(entity_spec['account'])

    for key, new_value in entity_spec.items():
        if new_value != existing_spec[key]:
            logger.debug('key="{:s}" existing_value="{:s}" new_value="{:s}"'.format(key, existing_spec[key], new_value))
            return True

    return False


def modify_entity(entity_type, entity_spec):
    args = ['sacctmgr', 'modify', '-i', ENTITY_TYPE_MAP[entity_type], 'where']
    for id_field in ENTITY_ID_FIELDS[entity_type]:
        args.append('{:s}={:s}'.format(id_field, entity_spec[id_field]))
    args.append('set')
    for key, value in entity_spec.items():
        if key not in ENTITY_ID_FIELDS[entity_type]:
            args.append('{:s}={:s}'.format(key, value))
    run_cmd(args)


def create_or_modify_entity(entity_type, entity_spec, dry_run=False):
    r = entity_repr(entity_type, entity_spec)

    if not entity_exists(entity_type, entity_spec):
        if dry_run:
            logger.warning('Would create {:s}.'.format(r))
            return
        create_entity(entity_type, entity_spec)
        if entity_exists(entity_type, entity_spec):
            logger.warning('Created {:s}.'.format(r))
        else:
            logger.error('Tried to create {:s}, but it did not do anything.'.format(r))
    elif entity_needs_modify(entity_type, entity_spec):
        if dry_run:
            logger.warning('Would modify {:s}.'.format(r))
            return
        modify_entity(entity_type, entity_spec)
        if entity_needs_modify(entity_type, entity_spec):
            logger.error('Tried to modify {:s}, but it did not do anything.'.format(r))
        else:
            logger.warning('Modified {:s}.'.format(r))
    else:
        logger.info('{:s} is up-to-date.'.format(r))


def list_entities(entity_type):
    args = [
        'sacctmgr', 'list', '-P', ENTITY_TYPE_MAP[entity_type],
        'format={:s}'.format(','.join(ENTITY_ID_FIELDS[entity_type])),
    ]
    if entity_type == 'association':
        args.append('withassoc')
    result = run_cmd(args)

    stdout_lines = result.stdout.strip().split('\n')
    keys = [k.strip().lower() for k in stdout_lines[0].strip().split('|')]
    return [
        dict(zip(
            keys,
            [v.strip() for v in row.strip().split('|')],
        ))
        for row in stdout_lines[1:]
    ]


def delete_entity(entity_type, entity_spec, dry_run=False):
    r = entity_repr(entity_type, entity_spec)

    if dry_run:
        logger.warning('Would delete {:s}.'.format(r))
        return

    args = ['sacctmgr', 'delete', '-i', ENTITY_TYPE_MAP[entity_type],  'where']
    for id_field in ENTITY_ID_FIELDS[entity_type]:
        args.append('{:s}={:s}'.format(id_field, entity_spec[id_field]))
    subprocess.run(args, check=True)
    if entity_exists(entity_type, entity_spec):
        logger.error('Tried to delete {:s}, but it did not do anything.'.format(r))
    else:
        logger.warning('Deleted {:s}.'.format(r))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('json_file')
    p.add_argument('--delete', action='store_true',
                   help="Delete unrecognized entities")
    p.add_argument('--dry-run', action='store_true',
                   help="Only print changes that would be made - don't take any actions")
    args = p.parse_args()

    data = parse_input(args.json_file)

    for entity_type in data.keys():
        if entity_type not in ENTITY_ID_FIELDS:
            raise ValueError('Entity type {:s} not supported.'.format(entity_type))

    # create or modify
    for entity_type in ENTITY_ID_FIELDS.keys():
        if entity_type in data:
            assert isinstance(data[entity_type], list)
            for entity in data[entity_type]:
                assert isinstance(entity, dict)
                create_or_modify_entity(entity_type, entity, dry_run=args.dry_run)

    # delete
    if args.delete:
        for entity_type in reversed(ENTITY_ID_FIELDS.keys()):
            new_entities = data.get(entity_type, [])
            for existing_entity in list_entities(entity_type):
                # FIXME N^2 runtime
                should_delete = True
                for new_entity in new_entities:
                    matches = True
                    for field in ENTITY_ID_FIELDS[entity_type]:
                        if new_entity[field] != existing_entity[field]:
                            matches = False
                            break
                    if matches:
                        should_delete = False
                        break
                if should_delete:
                    delete_entity(entity_type, existing_entity, dry_run=args.dry_run)


if __name__ == '__main__':
    main()
