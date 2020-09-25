#!/usr/bin/python
from flask import Flask, request
from subprocess import check_output as run
import datetime

file = "/www/install.log"

with open(file, "a") as install_file:
    install_file.write("== LOG OPENED ==\n")

app = Flask(__name__)

@app.route('/hosts')
def hosts():
    return run("/usr/local/bin/get_hosts.py")

@app.route('/log')
def log():
    f = open(file, 'r')
    return f.read()

@app.route('/install', methods=['POST'])
def install():
    if request.method == 'POST':
        with open(file, "a") as install_file:
            timestamp = datetime.datetime.now()
            ip = request.environ.get('HTTP_X_REAL_IP', request.remote_addr)
            action = request.form['action']
            print timestamp, ip
            install_file.write("%s: %s - %s\n" % (timestamp, action, ip))
    return 'done'

if __name__ == '__main__':
    app.run(port=5000, threaded=True)

#TODO:
# add start/end log entries for install
# busybox doesn't have curl, but can use wget:
# wget --post-data "ip=1.2.3.4" 192.168.1.1/install
