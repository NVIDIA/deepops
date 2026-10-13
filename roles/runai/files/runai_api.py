#!/usr/bin/env python3
"""Register a Run:ai cluster with the local control plane and print its Helm values.

Called by the runai role (platform mode). Credentials come from the environment
(RUNAI_USERNAME, RUNAI_PASSWORD), never from arguments, and are never printed.
Prints one JSON object: {"values": {...}, "cluster_uid": "...", "created": bool}.
Exit 0 ok, 1 API/HTTP failure, 2 bad input.
"""
import argparse
import http.client
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.parse

SET_RE = re.compile(r"--set(?:-string)?[ =]+([A-Za-z0-9_.\[\]-]+)=(\"[^\"]*\"|'[^']*'|[^\s\\]+)")
KEY_RE = re.compile(r"^([A-Za-z0-9_-]+)(?:\[(\d+)\])?$")


class ApiError(Exception):
    pass


def parse_set_args(text):
    pairs = {}
    for key, value in SET_RE.findall(text or ""):
        if len(value) >= 2 and value[0] in "\"'" and value[-1] == value[0]:
            value = value[1:-1]
        pairs[key] = value
    return pairs


def nest(pairs):
    out = {}
    for dotted, value in pairs.items():
        node = out
        parts = dotted.split(".")
        for i, part in enumerate(parts):
            m = KEY_RE.match(part)
            if not m:
                raise ApiError("unsupported Helm key in installation string")
            key, index = m.group(1), m.group(2)
            last = i == len(parts) - 1
            if index is None:
                if last:
                    node[key] = value
                else:
                    node = node.setdefault(key, {})
            else:
                lst = node.setdefault(key, [])
                while len(lst) <= int(index):
                    lst.append({})
                if last:
                    lst[int(index)] = value
                else:
                    node = lst[int(index)]
    return out


class Client:
    def __init__(self, domain, ip, ca_file, timeout=30):
        self.domain, self.ip, self.timeout = domain, ip or domain, timeout
        self.context = ssl.create_default_context(cafile=ca_file or None)
        self.bearer = ""

    def request(self, method, path, body=None, form=None):
        headers = {"Accept": "application/json"}
        data = None
        if form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if self.bearer:
            headers["Authorization"] = "Bearer " + self.bearer
        try:
            sock = socket.create_connection((self.ip, 443), self.timeout)
            conn = http.client.HTTPSConnection(self.domain, 443, context=self.context, timeout=self.timeout)
            conn.sock = self.context.wrap_socket(sock, server_hostname=self.domain)
            conn.request(method, path, body=data, headers=headers)
            resp = conn.getresponse()
            raw = resp.read(4 * 1024 * 1024)
            conn.close()
        except (OSError, ssl.SSLError, http.client.HTTPException) as exc:
            raise ApiError("%s %s failed: %s" % (method, path.split("?")[0], type(exc).__name__))
        if resp.status >= 300:
            raise ApiError("%s %s returned HTTP %d" % (method, path.split("?")[0], resp.status))
        try:
            return json.loads(raw) if raw else {}
        except ValueError:
            raise ApiError("%s %s returned invalid JSON" % (method, path.split("?")[0]))

    def login(self, user, pw):
        doc = self.request("POST", "/api/v2/token",
                           form={"grant_type": "password", "username": user, "password": pw})
        self.bearer = doc.get("access_token", "")
        if not self.bearer:
            raise ApiError("login returned no access token")


def wait_for_api(client, user, pw, wait):
    deadline = time.time() + wait
    last = ""
    while True:
        try:
            client.login(user, pw)
            return
        except ApiError as exc:
            last = str(exc)
        if time.time() >= deadline:
            raise ApiError("control plane did not accept the login in time (%s)" % last)
        time.sleep(10)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0], allow_abbrev=False)
    p.add_argument("--domain", required=True)
    p.add_argument("--resolve-ip", default="")
    p.add_argument("--ca-file", default="")
    p.add_argument("--cluster-name", required=True)
    p.add_argument("--chart-version", required=True)
    p.add_argument("--wait", type=int, default=600, help="seconds to wait for the control plane")
    args = p.parse_args(argv)
    user, pw = os.environ.get("RUNAI_USERNAME", ""), os.environ.get("RUNAI_PASSWORD", "")
    if not user or not pw:
        print("error: RUNAI_USERNAME and RUNAI_PASSWORD must be set", file=sys.stderr)
        return 2
    client = Client(args.domain, args.resolve_ip, args.ca_file)
    try:
        wait_for_api(client, user, pw, args.wait)
        listing = client.request("GET", "/api/v1/clusters")
        items = listing if isinstance(listing, list) else listing.get("clusters", [])
        found = [c for c in items if c.get("name") == args.cluster_name]
        created = not found
        if found:
            uid = found[0]["uuid"]
        else:
            uid = client.request("POST", "/api/v1/clusters", body={"name": args.cluster_name})["uuid"]
        info = client.request(
            "GET", "/api/v1/clusters/%s/cluster-install-info?version=%s"
            % (urllib.parse.quote(uid), urllib.parse.quote(args.chart_version)))
        pairs = parse_set_args(info.get("installationStr", ""))
        if info.get("bootstrapToken"):
            pairs["controlPlane.bootstrapToken"] = info["bootstrapToken"]
        for needed in ("controlPlane.url", "cluster.uid"):
            if needed not in pairs:
                raise ApiError("installation string has no %s" % needed)
        pairs = {k: v for k, v in pairs.items() if k.startswith(("controlPlane.", "cluster."))}
        print(json.dumps({"values": nest(pairs), "cluster_uid": uid, "created": created}))
        return 0
    except (ApiError, KeyError) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
