
export APPSDIR=/lustre/fsw/selene-admin/hplburnin-apps//apps

export HPCX_HOME=${APPSDIR}/hpcx-v2.7.0-gcc-MLNX_OFED_LINUX-5.0-1.0.0.0-ubuntu18.04-x86_64
export CUDA_HOME=${APPSDIR}/cuda/11.0.2

source ${HPCX_HOME}/hpcx-init.sh
hpcx_load

export PATH=${CUDA_HOME}/bin:${PATH}
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

echo " Loaded HPCX: ${HPCX_HOME}"
echo " UCX Version: $(ucx_info -v)"
echo "OMPI Version: $(ompi_info --version)"

