docker_ubuntu
========

Installs Docker on:

* Ubuntu 14.04+
* Debian Jessie (8.5+) and Stretch

This role attempts to make every reasonable effort to follow Docker's official installation instructions for Ubuntu and Debian.  

**Example Play**:

Very basic install utilizing the role defaults:

```
---
- name: Run docker.ubuntu
  hosts: docker
  roles:
    - angstwad.docker_ubuntu
```

Overriding the default configration is done by overriding the role's default variables:

```
- name: Install Docker
  hosts: all
  roles:
    - role: angstwad.docker_ubuntu
      ssh_port: 2222
      kernel_pkg_state: present
```


Requirements
------------

Requires python-pycurl for apt modules.

Role Variables
--------------

Please see [defaults/main.yml](https://github.com/angstwad/docker.ubuntu/blob/master/defaults/main.yml) for a comprehensive list of variables that can be overridden.

Dependencies
------------

None.

Testing
-------

To test the role in a Vagrant environment just run `vagrant up`.  This will
create some VMs:

* Ubuntu 12.04
* Ubuntu 14.04
* Ubuntu 16.04
* Debian Jessie 8.5
* Debian Stretch 9.0

and it will provision them by applying this role with Ansible.

Requires `ansible-playbook` to be in the path.

License
-------

Apache v2.0
