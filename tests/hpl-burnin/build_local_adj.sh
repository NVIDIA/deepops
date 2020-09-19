#!/bin/bash 
#Updates by ADJ to have options on what dependencies to install for the HPL Burn-In Test


#Usage instructions for build dependencies script
print_usage() {
   cat << EOF

${0} [options]

Set the HPL Burn In Test Script Dependencies to be built for the cluster under test. 

Options:
    -c|--cuda <CUDA>
        * Set to 0 in order to not build CUDA. The default is to installfor HPL Burn In Rev 1.0 is 11.0.2
    -m|--mofed <OFED_VERSION_MAJOR>
        * Set the MOFED Major Version to install the correct version of HPC-X for the OFED version on the cluster compute nodes. FOR DGX A100 this is 5.0, DGX-1/2 it is 4.7
    -u|--ucx <HPC-X>
	* Set to 0 in order to not utilize HPC-X Cluster Kit to install OpenMPI and UCX
EOF

exit
}

#we want to select if we want to build cuda, and then specify what version to build.  For HPC-X we will always install it with this script, otherwise why would you run it in the first place?  We could do the dependency check first and show what versions are installed if they are.  Then exit if it is already set up?


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
        echo "CUDA will NOT be installed";
else
	echo "CUDA will be installed"
fi

BUILD_CUDA=${buildcuda:-1}
#echo "BUILD_CUDA=$BUILD_CUDA"
export BUILD_CUDA

if [ x${buildhpcx} == x"0" ]; then
        echo "OpenMPI and UCX 1.9 will NOT be installed via HPCX";
else
        echo "OpenMPI and UCX 1.9 will be installed via HPCX";
fi

BUILD_HPCX=${buildhpcx:-1}
export BUILD_HPCX
#export BUILD_HPCX=${BUILD_HPCX:-1}
#echo "BUILD_HPCX=$BUILD_HPCX"


#If both options for HPC-X and CUDA say do not install, then exit
#if [ $BUILD_HPCX==0 -a $BUILD_CUDA==0 ]; then
#	echo "Why even bother running this script?";
#	exit
#fi

ofed_major=${ofed_major:-5.0}
echo "HPC-X for Mellanox OFED $ofed_major will be installed from"

case ${ofed_major} in
   "5.0") HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v2.7/hpcx-v2.7.0-gcc-MLNX_OFED_LINUX-5.0-1.0.0.0-ubuntu18.04-x86_64.tbz"; echo $HPCX_URL ;;
   "4.7") HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v2.7/hpcx-v2.7.0-gcc-MLNX_OFED_LINUX-4.7-1.0.0.1-ubuntu18.04-x86_64.tbz"; echo $HPCX_URL ;;
   *) echo "Unable to find a matching MOFED version for HPCX, exiting." & exit 1 ;;
esac

#sets the directory where the burn in test is located, then sets where CUDA and HPC-X will downloaded and built
export BASEDIR=${BASEDIR:-$(cd $(dirname 0) && pwd)}
export BUILDDIR=${BUILDDIR:-/tmp/build.$$}
echo $BASEDIR
echo $BUILDDIR

APPSDIR=${BASEDIR}/apps

mkdir -p $APPSDIR
mkdir -p $BUILDDIR

#for HPL Burn In test we want the default value for cuda to be 11.0.2.  To Do: Add a Check to see if CUDA is installed, if so show revision and abort if it is not rev 11.0.2

#Variable definitions for CUDA and HPC-X Installs

#CUDA Install Variables
CUDA_VERSION=11.0.2
CUDA_HOME=${APPSDIR}/cuda/${CUDA_VERSION}
mkdir -p ${CUDA_HOME}
echo $CUDA_HOME

#HPCX Install Variables

#Uses HPC-X Download location based on MOFED selection, then determines appropriate file names and directories
#HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v2.7/hpcx-v2.7.0-gcc-MLNX_OFED_LINUX-5.0-1.0.0.0-ubuntu18.04-x86_64.tbz"
HPCX_VERSION=$(echo $HPCX_URL | grep -o '[^/]*$' | cut -f5-6 -d-)
#echo $HPCX_VERSION
HPCX_FN=$(basename ${HPCX_URL})
HPCX_DIR=$(basename ${HPCX_FN} .tbz)

#Build CUDA and HPC-X if selected to do so (Yes by default)

#Build CUDA from Run File
if [ $BUILD_CUDA == 1 ]; then
    echo ""
    echo "INFO: Installing CUDA ${CUDA_VERSION}"
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

   #change to build directory where the CUDA run file is downloaded.  Remove the file if it is already present. Then run the installer to install the toolkit only. Not sure i understand why this wasn't done the same way as for HPC-X
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
	ofed_version=5.0-2.1.8
	ofed_version_major=$(echo $ofed_version | awk '{print $NF}' | cut -f1 -d-)
#	echo $ofed_version_major

	hpcx_version=$(echo $HPCX_URL | grep -o '[^/]*$' | cut -f5-6 -d-)
	hpcx_version_major=$(echo $hpcx_version | grep -o '[^/]*$' | cut -f1 -d-)
#	echo $hpcx_version

	if [ ${ofed_version_major} != ${hpcx_version_major} ]; then
		echo "Error, the local ofed version ($ofed_version} is not correct for the request HPCX version {$hpcx_version_major}."
		#echo "The build script needs to be updated to match the local MOFED version."
		echo "Please use the correct --mofed argument to match the local MOFED version."
		echo "./build_local.sh --mofed $ofed_version_major or"
		echo "./build_local.sh -m $ofed_version_major"
		exit
	fi
	
	if [ -f $BUILDDIR/$HPCX_FN ]; then
		rm $BUILDDIR/$HPCX_FN
	fi
	wget -q -nc --no-check-certificate -P $BUILDDIR $HPCX_URL
	cd $APPSDIR
	tar -xjf $BUILDDIR/$HPCX_FN

	echo ""
	echo "INFO: Done installing HPCX"
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

echo \" Loaded HPCX: \${HPCX_HOME}\"
echo \" UCX Version: \$(ucx_info -v)\"
echo \"OMPI Version: \$(ompi_info --version)\"
" > setenv.sh

echo "Created setenv.sh to setup your environment.  Execute 'source setenv.sh' to enable."


