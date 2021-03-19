help([[
Setup environment to run rootless docker.

Sets the XDG_RUNTIME_DIR to /var/tmp/xdg_runtime_dir_<userid>
Sets the DOCKER_HOST to "unix://${XDG_RUNTIME_DIR}/docker.sock"
Adds the following scripts to the path:
  start_docker_rootless.sh
  stop_docker_rootless.sh


Start rootless docker daemon by calling:
  $ start_docker_rootless.sh

Then use regular docker commands i.e. docker run, pull, push, etc.
Specify "--gpus" option as needed.

To stop/kill the rootless docker daemon call:
  $ stop_docker_rootless.sh

Refer to help of the scripts.
  $ start_docker_rootless.sh -h
To run without verbose rootless docker messages run:
  $ start_docker_rootless.sh --quiet

]])


prepend_path("PATH", "{{ rootlessdocker_install_dir }}/bin")

local userid = capture("id -u")
local userid = string.gsub(userid, '%s+', '')
local xdg_runtime_dir = "/var/tmp/xdg_runtime_dir_" .. userid
local docker_dataroot = "/var/tmp/docker-container-storage-" .. userid

pushenv("XDG_RUNTIME_DIR", xdg_runtime_dir)
setenv("DOCKER_HOST", "unix://"..xdg_runtime_dir.."/docker.sock")
setenv("DOCKER_DATAROOT", docker_dataroot)
