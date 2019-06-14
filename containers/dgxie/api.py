#!/usr/bin/python
from flask import Flask, abort, request
import json
import datetime
import re
import os

app = Flask(__name__)

@app.route('/v1/boot/<mac>')
def pxe(mac):
    '''See https://github.com/danderson/netboot/blob/master/pixiecore/README.api.md for API specs'''
    # load machine profiles for each call so we can re-load changes from disk
    jf = open('/etc/machines/machines.json', 'r')
    machines = json.load(jf)
    jf.close()

    if "HTTP_PORT" in os.environ.keys():
        http_port = os.environ['HTTP_PORT']
    else:
        http_port = "13370"

    # return profile in json for matching machine
    for machine in machines:
        if 'mac' in machines[machine] and re.match(machines[machine]['mac'], mac):
            machines[machine]['mac'] = mac

            machines[machine]['kernel'] = machines[machine]['kernel'].replace("$HTTP_PORT", http_port)
            if 'cmdline' in machines[machine]:
                machines[machine]['cmdline'] = machines[machine]['cmdline'].replace("$HTTP_PORT", http_port)
            if 'initrd' in machines[machine]:
                for i in range(len(machines[machine]['initrd'])):
                    machines[machine]['initrd'][i] = machines[machine]['initrd'][i].replace("$HTTP_PORT", http_port)

            return json.dumps(machines[machine])
    abort(404)

@app.route('/install', methods=['POST'])
def install():
    if request.method == 'POST':
        timestamp = datetime.datetime.now()
        ip = request.environ.get('HTTP_X_REAL_IP', request.remote_addr)
        action = request.form['action']
        print timestamp, ip
    return 'done'

if __name__ == '__main__':
    app.run(port=9090, threaded=True)
