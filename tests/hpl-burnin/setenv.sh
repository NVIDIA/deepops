APPSDIR=/lustre/fsw/selene-admin/ctierney/apps
CUDA_HOME=${APPSDIR}/cuda/11.0.2
UCX_HOME=${APPSDIR}/ucx/1.9.0-rc1
MPI_HOME=${APPSDIR}/openmpi/4.0.4


export PATH=${CUDA_HOME}/bin:${UCX_HOME}/bin:${MPI_HOME}/bin:${PATH}
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${UCX_HOME}/lib:${MPI_HOME}/lib:${LD_LIBRARY_PATH}


