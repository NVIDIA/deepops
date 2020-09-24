#!/bin/bash 
#Install dependencies for the HPL Burn-In Test.  It is assumed that Slurm Cluster Manger is configured with PMIx and hwloc. This script specifically installs the CUDA Toolkit by its .run installer, and UCX and OpenMPI via the HPC-X Software Toolkit. 


#Usage instructions for build dependencies script
print_usage() {
   cat << EOF

${0} [options]

Select the HPL Burn In Test Script dependencies to be built for the cluster under test. 

When ${0} is run with no options, it defaults to installing:
CUDA Toolkit 11.0.2
HPC-X v2.7 which install UCX 1.9 and Open MPI 4.0.4

Options:
    -c|--cuda <CUDA Toolkit>
        * Set to 0 in order to not build the CUDA toolkit.  For a Slurm cluster set up by DeepOps, CUDA is setup by default so only HPC-X needs to be run. 
    -m|--mofed <Mellanox OFED major version>
        * Define the MOFED major version to install the correct version of HPC-X for the OFED version on the cluster compute nodes. FOR DGX A100 this is 5.0, DGX-1/2 it is 4.7
    -u|--ucx <Install OpenMPI and UCX via HPC-X>
	* Set to 0 in order to not utilize HPC-X Cluster Kit to install OpenMPI and UCX
EOF

exit
}



while [ $# -gt 0 ]; do
        case "$1" in
                -h|--help) print_usage ; exit 0 ;;
                -c|--cuda) buildcuda="$2"; shift 2 ;;
                -m|--mofed) ofed_major="$2"; shift 2 ;;
                -u|--ucx) buildhpcx="$2"; shift 2;;  
		*) echo "Option <$1> Not understood" ; exit 1 ;;

        esac
done

#Next steps after CUDA build option selected and MOFED Specified


if [ x${buildcuda} == x"0" ]; then
        echo "CUDA will NOT be installed"
else
	echo "CUDA will be installed"
fi

BUILD_CUDA=${buildcuda:-1}
#echo BUILD_CUDA=$BUILD_CUDA"
export BUILD_CUDA

if [ x${buildhpcx} == x"0" ]; then
        echo "OpenMPI and UCX 1.9 will NOT be installed via HPCX"
else
        echo "OpenMPI and UCX 1.9 will be installed via HPCX"
fi

BUILD_HPCX=${buildhpcx:-1}
export BUILD_HPCX
#echo "BUILD_HPCX=$BUILD_HPCX"


#If both options for HPC-X and CUDA say do not install, then exit
#if [ ${BUILD_CUDA} && ${BUILD_HPCX} == 0 ]; then
#	echo "Terminating script, no installations specified."
# 	exit	
#fi

ofed_major=${ofed_major:-5.0}
echo "HPC-X for Mellanox OFED $ofed_major will be downloaded from"

case ${ofed_major} in
   "5.0") HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v2.7/hpcx-v2.7.0-gcc-MLNX_OFED_LINUX-5.0-1.0.0.0-ubuntu18.04-x86_64.tbz"; echo $HPCX_URL ;;
   "4.7") HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v2.7/hpcx-v2.7.0-gcc-MLNX_OFED_LINUX-4.7-1.0.0.1-ubuntu18.04-x86_64.tbz"; echo $HPCX_URL ;;
   *) echo "Unable to find a matching MOFED version for HPCX, exiting." & exit 1 ;;
esac

#sets the directory where the burn in test is located, then sets where CUDA and HPC-X will downloaded and built
export BASEDIR=${BASEDIR:-$(cd $(dirname 0) && pwd)}
export BUILDDIR=${BUILDDIR:-/tmp/build.$$}
#echo $BASEDIR
#echo $BUILDDIR

APPSDIR=${BASEDIR}/apps

mkdir -p $APPSDIR
mkdir -p $BUILDDIR


#Variable definitions for CUDA and HPC-X Installs

#CUDA Install Variables
CUDA_VERSION=11.0.2
CUDA_HOME=${APPSDIR}/cuda/${CUDA_VERSION}
mkdir -p ${CUDA_HOME}
#echo $CUDA_HOME

#HPCX Install Variables

#HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v2.7/hpcx-v2.7.0-gcc-MLNX_OFED_LINUX-5.0-1.0.0.0-ubuntu18.04-x86_64.tbz"
HPCX_VERSION=$(echo $HPCX_URL | grep -o '[^/]*$' | cut -f5-6 -d-)
#echo $HPCX_VERSION
HPCX_FN=$(basename ${HPCX_URL})
HPCX_DIR=$(basename ${HPCX_FN} .tbz)

#Build CUDA Toolkit and HPC-X if selected to do so (Yes by default)

#Build CUDA Toolkit from Run File
if [ $BUILD_CUDA == 1 ]; then
    echo ""
    echo "INFO: Installing CUDA Toolkit ${CUDA_VERSION}"
    echo ""

    CLOG=/tmp/cuda-installer.log
    if [ -f ${CLOG} ]; then
	    echo ""
	    echo "INFO: The file ${CLOG} was found, trying to remove".
	    rm -f ${CLOG}
            if [ -f ${CLOG} ]; then
		    echo ""
		    echo "ERROR: Unable to remove ${CLOG} before installation of CUDA."
		    echo "ERROR: Existence of this file without write permission will"

echo "ERROR: cause the instalation of CUDA to trigger a segementation"
		    echo "ERROR: fault.  Please have the file removed, and try the"
		    echo "ERROR: Installation again."
		    echo ""
		    exit 1
            fi
	    echo "INFO: File ${CLOG} has been removed."
	    echo ""
    fi

#Change to build directory where the CUDA run file is downloaded.  Remove the file if it is already present. Then run the installer to install the toolkit only. 
    cd ${BUILDDIR}
    CUDAPATH=http://developer.download.nvidia.com/compute/cuda/11.0.2/local_installers/cuda_11.0.2_450.51.05_linux.run
    CUDAFN=$(basename ${CUDAPATH})
    rm -f ${CUDAFN}
    wget http://developer.download.nvidia.com/compute/cuda/11.0.2/local_installers/${CUDAFN}

    sh ${CUDAFN} --installpath=${CUDA_HOME} --silent --toolkit

    if [ $? -ne 0 ]; then
	echo "ERROR: Install of CUDA failed.  Exiting"
   fi
   echo ""
   echo "INFO: Done installing CUDA"
fi


#Build HPC-X and install UCX and OpenMPI
if [ $BUILD_HPCX == 1 ]; then
	# First some sanity checking to make sure that the right version
	echo ""
	echo "INFO: Installing HPCX for MLNX OFED ${HPCX_VERSION}"

#On Login nodes where there is no mellanox adapter, this check will fail.  Perhaps do an srun to use a compute node on the test cluster and check its OFED, since it will be the same as all the nodes in the POD
#	if [ x"$(which ofed_info)" == x"" ]; then
#		echo ""
#		echo "Error, unable to find ofed_info.  IB or RoCE is not enabld on this system.  Exiting"
#		exit
#	fi

#	ofed_version=$(ofed_info -n)
# Test value of above command from return value given by Selene node
#	ofed_version=5.0-2.1.8
#	ofed_version_major=$(echo $ofed_version | awk '{print $NF}' | cut -f1 -d-)
#	echo $ofed_version_major

#	hpcx_version=$(echo $HPCX_URL | grep -o '[^/]*$' | cut -f5-6 -d-)
#	hpcx_version_major=$(echo $hpcx_version | grep -o '[^/]*$' | cut -f1 -d-)
#	echo $hpcx_version

#	if [ ${ofed_version_major} != ${hpcx_version_major} ]; then
#		echo "Error, the local ofed version ($ofed_version} is not correct for the request HPCX version {$hpcx_version_major}."
		#echo "The build script needs to be updated to match the local MOFED version."
#		echo "Please use the correct --mofed argument to match the local MOFED version."
#		echo "${0} --mofed $ofed_version_major or"
#		echo "${0} -m $ofed_version_major"
#		exit
#	fi
	
	if [ -f $BUILDDIR/$HPCX_FN ]; then
		rm $BUILDDIR/$HPCX_FN
	fi
	wget -q -nc --no-check-certificate -P $BUILDDIR $HPCX_URL
	cd $APPSDIR
	tar -xjf $BUILDDIR/$HPCX_FN

	echo ""
	echo "INFO: Done installing HPC-X"
	else exit
fi

# create setenv.sh script
cd ${BASEDIR}

echo "
export APPSDIR=${APPSDIR}

export HPCX_HOME=\${APPSDIR}/$HPCX_DIR
export CUDA_HOME=\${APPSDIR}/cuda/${CUDA_VERSION}

source \${HPCX_HOME}/hpcx-init.sh
hpcx_load

export PATH=\${CUDA_HOME}/bin:\${PATH}
export LD_LIBRARY_PATH=\${CUDA_HOME}/lib64:\${LD_LIBRARY_PATH}

echo \" Compute Node Driver Version: \$(nvidia-smi | grep -i nvidia-smi | awk '{print $3}') 
echo \" CUDA Toolkit Version: \$(nvcc -V)\"
echo ""
echo \" Loaded HPCX: \${HPCX_HOME}\"
echo ""
echo \" UCX Version: \$(ucx_info -v)\"
echo ""
echo \"OMPI Version: \$(ompi_info --version)\"
" > setenv.sh

echo "Created setenv.sh to setup your environment.  Execute 'source setenv.sh' to enable."


#############
#Compute Node Driver Check
#NV_DRIVER_MIN_VER=450
#NV_DRIVER_DETECTED_VERSION=$(srun -N1 -n1 -G1 nvidia-smi | grep -i nvidia-smi | awk '{print $3}')
#NV_DRIVER_DETECTED_MAJ=$(echo $NV_DRIVER_DETECTED_VERSION | awk '{print $NF}' | cut -f1 -d.) 
#echo $NV_DRIVER_DETECTED_VERSION 
#echo $NV_DRIVER_DETECTED_MAJ

#if [ "$NV_DRIVER_DETECTED_MAJ" <  ${NV_DRIVER_MIN_VER} ] ; then
#echo " ";
#echo " Driver branch ${NV_DRIVER_DETECTED_MAJ} installed on the compute nodes is insufficient for the CUDA 11.0 Toolkit. / It must be ${NV_DRIVER_MIN_VER} or greater "
#else
#echo "The compute node driver branch ${NV_DRIVER_DETECTED_MAJ} is sufficient for the CUDA 11.0 Toolkit"
#fi

