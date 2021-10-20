help([[
Setup environment to run rootless docker. Load this module within a Slurm
reservation on a compute node.

When loaded:
  - Sets the XDG_RUNTIME_DIR to "/var/tmp/userid-<numeric uid>-jobid-${SLURM_JOB_ID}/xdg_runtime_dir"
  - Sets the DOCKER_HOST to "unix://${XDG_RUNTIME_DIR}/docker.sock"
  - Sets the DOCKER_DATAROOT to "/var/tmp/userid-<numeric uid>-jobid-${SLURM_JOB_ID}/docker-container-storage"
  - Adds the following scripts to the path:
      start_rootless_docker.sh
      stop_rootless_docker.sh

The scripts rely on the environment variables: XDG_RUNTIME_DIR, DOCKER_HOST,
DOCKER_DATAROOT. 

Start rootless docker daemon by calling:
  $ start_rootless_docker.sh
To run without verbose rootless docker messages run:
  $ start_rootless_docker.sh --quiet
Refer to the help of the scripts.
  $ start_rootless_docker.sh -h

Once the rootless docker daemon is started use regular docker commands i.e.
docker run, pull, push, etc. Specify "--gpus" option as needed.

To stop/kill the rootless docker daemon call:
  $ stop_rootless_docker.sh

Upon Slurm job session ending rootless docker will stop and the directories
used by rootless docker are removed. The following directory and all its
contents are removed: "/var/tmp/userid-<numeric uid>-jobid-${SLURM_JOB_ID}".

]])


prepend_path("PATH", "{{ rootlessdocker_install_dir }}/bin")

local slurm_jobid=os.getenv("SLURM_JOB_ID") or ""

if (slurm_jobid == "") then
  LmodMessage ("WARNING: SLURM JOBID NOT SET.")
end

local userid = capture("id -u")
local userid = string.gsub(userid, '%s+', '')
local basedir = "/var/tmp/userid-"..userid.."-jobid-"..slurm_jobid
local xdg_runtime_dir = basedir.."/xdg_runtime_dir"
local docker_dataroot = basedir.."/docker-container-storage"

pushenv("XDG_RUNTIME_DIR", xdg_runtime_dir)
setenv("DOCKER_HOST", "unix://"..xdg_runtime_dir.."/docker.sock")
setenv("DOCKER_DATAROOT", docker_dataroot)
