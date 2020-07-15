export EASYBUILD_PREFIX={{ sm_prefix }}
export EASYBUILD_MODULES_TOOL=Lmod
module purge
unset $(env | grep EBROOT | awk -F'=' '{print $1}')
module load EasyBuild
