Setting up an offline mirror for HTTP downloads
===============================================

While most of the software installed by DeepOps makes use of package repositories, some software is downloaded directly over HTTP as raw files.

To support these installations in offline environments, you may need to provide alternate download URLs for DeepOps to use.
This requires that an HTTP (web) server be present and available to host files.


Setting up the server
---------------------

Many offline environments already have a convenient HTTP server for hosting web pages or other downloads.
If your environment already has a preferred server to use for downloads, you may be able to use that!

If this doesn't exist already, the following process shows a minimal approach using an Apache httpd server.

First, in the offline network, pick a machine to use as your HTTP server.
We will assume the use of the Apache httpd server and that the web root is `/var/www/html`:

```
$ sudo apt update
$ sudo apt install apache2
$ sudo mkdir /var/www/html/downloads
```

Then, for any files you need to make available for download, simply copy these files to `/var/www/html/downlaods`.


Configuring DeepOps
-------------------

To configure DeepOps to make use of this server, you will need to configure the specific variables for the download URL of each file.
The best place to find these variables is the `defaults/main.yml` file of each role you plan to make use of.

For example, in the [nvidia-docker role](https://github.com/NVIDIA/ansible-role-nvidia-docker), the wrapper script is downloaded from the [nvidia-docker Github repositories](https://raw.githubusercontent.com/NVIDIA/nvidia-docker/master/nvidia-docker).

To mirror this file offline, you would download the script and place it on your offline repo server, then configure the `nvidia_docker_wrapper_url` variable with the alternate URL.

Documentation on specific offline workflows (such as the [NGC ready offline doc](./ngc-ready.md)) may list specific files that need to be downloaded for those workflows.
