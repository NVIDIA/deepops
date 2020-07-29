#!/bin/bash 

BASEDIR=/lustre/fsw/selene-admin/ctierney
BUILDDIR=${BASEDIR}/build
APPSDIR=${BASEDIR}/apps

mkdir -p $APPSDIR
mkdir -p $BUILDDIR

CUDA_HOME=${APPSDIR}/cuda/11.0.2
mkdir -p ${CUDA_HOME}

UCX_VERSION=1.8.1
UCX_HOME=${BASEDIR}/apps/ucx/${UCX_VERSION}

MPI_VERSION=4.0.4
MPI_HOME=${BASEDIR}/apps/openmpi/${MPI_VERSION}

cd ${BUILDDIR}

CUDAPATH=http://developer.download.nvidia.com/compute/cuda/11.0.2/local_installers/cuda_11.0.2_450.51.05_linux.run
CUDAFN=$(basename ${CUDAPATH})
rm ${CUDAFN}
#wget http://developer.download.nvidia.com/compute/cuda/11.0.2/local_installers/${CUDAFN}
#sh ${CUDAFN} --installpath=${CUDA_HOME} --silent --toolkit

if [ $? -ne 0 ]; then
	echo "Install of CUDA failed.  Exiting"
	exit
fi

curl -fSsL "https://github.com/openucx/ucx/releases/download/v1.8.1/ucx-${UCX_VERSION}.tar.gz" | tar xz && \
    cd ucx-${UCX_VERSION}  && \
    ./configure     \
        --prefix=${UCX_HOME}        \
        --enable-shared             \
        --disable-static            \
        --disable-doxygen-doc       \
        --enable-optimizations      \
        --enable-cma                \
        --enable-devel-headers      \
        --with-cuda=${CUDA_HOME} \
        --with-verbs                \
        --with-dm                   \
        --with-gdrcopy=/usr/local   \
        --enable-mt                 \
        --with-mlx5-dv &&           \
    make -j 8 &&                      \
    make -j 8 install-strip

if [ $? -ne 0 ]; then
	echo "Install of UCX failed.  Exiting"
	exit
fi


curl https://download.open-mpi.org/release/open-mpi/v$(echo ${MPI_VERSION} | cut -f1,2 -d.)/openmpi-${MPI_VERSION}.tar.bz2 | tar xj
cd openmpi-${MPI_VERSION}

./configure                       \
    --prefix=${MPI_HOME}           \
    --enable-shared               \
    --disable-static              \
    --with-verbs                  \
    --with-cuda=${CUDA_HOME}   \
    --with-ucx=${UCX_HOME}         \
    --enable-mca-no-build=btl-uct \
    --with-pmix=internal          \
    --disable-getpwuid &&         \
    make -j 8 &&                        \
    make -j 8 install-strip


echo "Source setenv.sh to setup your environment"

