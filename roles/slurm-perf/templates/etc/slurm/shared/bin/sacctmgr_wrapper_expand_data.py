#!/usr/bin/env python3

import argparse
import json


def main():
    p = argparse.ArgumentParser()
    p.add_argument('input_concise_data_file')
    p.add_argument('output_expanded_data_json_file')
    args = p.parse_args()

    print('Reading from {:s} ...'.format(args.input_concise_data_file))
    if args.input_concise_data_file.lower().endswith(('.yml', '.yaml')):
        import yaml
        with open(args.input_concise_data_file) as infile:
            concise_data = yaml.load(infile.read())
    else:
        # assume json
        with open(args.input_concise_data_file) as infile:
            concise_data = json.load(infile)

    data = {}

    data['cluster'] = [concise_data['cluster']]
    data['qos'] = concise_data['qos']
    data['account'] = []
    for a in concise_data['accounts']:
        account_entity = a.copy()
        account_entity.pop('qos', None)
        data['account'].append(account_entity)

    data['association'] = []
    data['user'] = []
    for u in concise_data['users']:
        first_account = None
        accounts = u.pop('accounts')
        for a in accounts:
            if first_account is None:
                first_account = a['account']

            account_data = next(x for x in concise_data['accounts']
                                if x['account'] == a['account'])
            assoc_entity = {
                'cluster': data['cluster'][0]['cluster'],
                'user': u['user'],
            }

            qos = (a.pop('qos') if 'qos' in a
                   else account_data['qos'] if 'qos' in account_data
                   else None)
            if qos is not None:
                assoc_entity['qos'] = ','.join(qos)
                assoc_entity['defaultqos'] = qos[0]

            assoc_entity.update(a)
            data['association'].append(assoc_entity)

        user_entity = {
            'defaultaccount': first_account,
        }
        user_entity.update(u)
        data['user'].append(user_entity)

    print('Writing to {:s} ...'.format(args.output_expanded_data_json_file))
    with open(args.output_expanded_data_json_file, 'w') as outfile:
        outfile.write(json.dumps(data, indent=2))

    print('Done.')


if __name__ == '__main__':
    main()
