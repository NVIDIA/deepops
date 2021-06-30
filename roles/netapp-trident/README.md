netapp-trident
=========

Ansible role that can be used to deploy NetApp Trident within a Kubernetes cluster.

Requirements
------------

**Prerequisites:**

1. 'kubectl' must be installed on the target host.
2. '~/.kube/config' must be configured, on the target host, for access to the cluster that you wish to deploy Trident to.
3. 'helm' must be installed on the target host.

Role Variables
--------------

See defaults/main.yml, vars/main.yml

Dependencies
------------

Kubernetes must have already been deployed using DeepOps.

Example Playbooks
----------------

Note: Role must be invoked with "become: true", or playbook that invokes role must be executed by root user.

**Example Playbooks:**

Example A:

    - name: "Deploy NetApp Trident"
      hosts: localhost
      become: true
      become_method: sudo
      roles:
         - role: netapp-trident

Example B:

    - name: "Deploy NetApp Trident"
      hosts: kube-master
      become: true
      become_method: sudo
      roles:
        - role: netapp-trident

Example C:

    - name: "Deploy NetApp Trident"
      hosts: kube-master
      become: true
      become_method: sudo
      vars_files:
        - custom-vars.yml
      roles:
        - role: netapp-trident

**Example Inventory File:**

```
all:
  hosts:
    mgmt01:
      ansible_host: 192.168.1.210
      ip: 192.168.1.210
      access_ip: 192.168.1.210
    mgmt02:
      ansible_host: 192.168.1.211
      ip: 192.168.1.211
      access_ip: 192.168.1.211
    mgmt03:
      ansible_host: 192.168.1.212
      ip: 192.168.1.212
      access_ip: 192.168.1.212
    app01:
      ansible_host: 192.168.1.213
      ip: 192.168.1.213
      access_ip: 192.168.1.213
    app02:
      ansible_host: 192.168.1.214
      ip: 192.168.1.214
      access_ip: 192.168.1.214
    app03:
      ansible_host: 192.168.1.215
      ip: 192.168.1.215
      access_ip: 192.168.1.215
  children:
    kube-master:
      hosts:
        mgmt01:
        mgmt02:
        mgmt03:
    servers-dgx2:
      hosts:
        app01:
        app02:
        app03:
```
