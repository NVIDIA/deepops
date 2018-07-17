#!/usr/bin/python
from flask import Flask, abort, request
import json
import datetime

app = Flask(__name__)

@app.route('/v1/boot/<mac>')
def pxe(mac):
    # load machine profiles for each call so we can re-load changes from disk
    jf = open('/data/machines.json', 'r')
    machines = json.load(jf)
    jf.close()

    # return profile in json for matching machine
    for machine in machines:
        if 'mac' in machines[machine] and machines[machine]['mac'] == mac:
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
