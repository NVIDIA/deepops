#!/bin/bash
#location of HPL


### HERE we cannot do the trick of pulling the dirname off the script
### Because the batch systems may copy the script to a local location before
### Execution. So this means the path would be to a directory somewhere possibly
### in /tmp, not the real script directory.  The HPL_DIR should be set since
### it was determined in the launch script.

export HPL_DIR=${HPL_DIR:-$(pwd)} # Shared location where all HPL files are stored

export HPL_SCRIPTS_DIR=${HPL_SCRIPTS_DIR:-${HPL_DIR}} # Shared location where these scripts are stored
export HPL_FILE_DIR=${HPL_FILE_DIR:-${HPL_DIR}/hplfiles} # Shared location where .dat files are stored

export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

echo "NVCC Version: $(nvcc -V)"
echo "NVIDIA-SMI:"
nvidia-smi

echo "NUMACTL:"
numactl --show

#### Setup and Check Run Environment
if [ x"$(which mpirun)" == x"" ]; then
	echo "Unable to find mpirun.  Exiting"
	exit
fi
echo "MPI Version: $(mpirun --version)"

if [ ${SLURM_JOB_ID} ]; then
	JOBID=${SLURM_JOB_ID}
	NNODES=${SLURM_NNODES}
	NPROCS=${SLURM_NPROCS}
else
	JOBID=$(uname -n).$(date +%Y%m%d%H%M%S)
	if [ x"$MACHINE_FILE" == x"" ]; then
		echo "ERROR: Not running under a recognized workload management system.  Unable to find MACHINE_FILE.  Exiting"
	fi
	NNODES=$(cat $MACHINE_FILE | wc -l)
	NPROCS=0
	echo "Generic system support is not enabled yet".
	exit
fi

echo "JOBID: ${JOBID}"
echo "NNODES: ${NNODES}"
echo "NPROCS: ${NPROCS}  -- Number of GPUs to use"

export SYSTEM=${SYSTEM:-"dgx1v_16G"}
export GPUS_PER_NODE=${GPUS_PER_NODE:-"8"}

if [ x"${HPLDAT}" != x"" ]; then
	echo "Using predefined HPL.dat file: ${HPLDAT}"
	HPLFN=${HPLDAT}
else
	if [ ${GPUS_PER_NODE} == 8 ]; then
		case ${NNODES} in
			1) PxQ=4x2 ;;
			2) PxQ=4x4 ;;
			4) PxQ=8x4 ;;
			8) PxQ=8x8 ;;
			10) PxQ=10x8 ;;
			16) PxQ=16x8 ;;
			20) PxQ=20x8 ;;
			32) PxQ=16x16 ;;
			64) PxQ=32x16 ;;
	                *) echo "ERROR: There is no defined mapping for ${NNODES} nodes for system ${SYSTEM}.  Exiting" 
		esac
	elif [ ${GPUS_PER_NODE} == 16 ]; then
		case ${NNODES} in
			1) PxQ=4x4 ;;
			2) PxQ=8x4 ;;
			4) PxQ=8x8 ;;
                *) echo "ERROR: There is no defined mapping for ${NNODES} nodes for system ${SYSTEM}.  Exiting" 
		esac
	fi

	HPLFN=${HPL_FILE_DIR}/HPL.dat_${PxQ}_${SYSTEM}
fi
 
if [ ! -f $HPLFN ]; then
	echo "ERROR: Unable to find $HPLFN.  Exiting"
 	exit
fi

TEST_NAME=HPL-${SYSTEM}-${PxQ}
if [ x"${EXPDIR}" != x"" ]; then
	# just create an expname from expdir
	export EXPNAME="$(basename ${EXPDIR}).$(uname -n).${JOBID}"
else
	# create a unique expname 
	export EXPNAME=${EXPNAME}.$(uname -n).${JOBID}
	export EXPDIR=${HPL_DIR}/results/${EXPNAME}
fi

if [ ! -d ${HPL_DIR}/results ]; then
	mkdir ${HPL_DIR}/results
	if [ $? -ne 0 ]; then
		echo "ERROR: Unable to create directory: ${HPL_DIR}/results."
		exit
	fi
fi

if [ ! -d ${EXPDIR} ]; then
    mkdir -p ${EXPDIR}
    if [ $? -ne 0 ]; then
	echo "ERROR: unable to create experiment directory: ${EXPDIR}"
	exit 
    fi
fi


echo "" 
echo "EXPDIR: ${EXPDIR}"
echo "EXPERIMENT NAME: ${EXPNAME}" 
echo "HPL File: ${HPLFN}"

echo "" 
echo "=============================" 
echo "HPL.dat File" 
echo "=============================" 
cat ${HPLFN} 
echo "=============================" 
echo "=============================" 
echo "" 

### Create working directory in which to work
WORKDIR=${HPL_DIR}/tmp/tmp.${JOBID}
mkdir -p ${WORKDIR} 
if [ $? -ne 0 ]; then
	echo "ERROR: Unable to create working directory $WORKDIR.  Exiting"
	exit 1
fi

## Create working runtime environment
cp $HPLFN $WORKDIR/HPL.dat
cp bind.sh $WORKDIR/
cd $WORKDIR 

#### Confirm mpirun is installed correctly
if [ x"$(which mpirun)" ==  x"" ]; then
	echo "Error, unable to find mpirun.  Installation is broken.  Exiting."
	exit
fi

#### Set Node information
gpuclock=${NV_GPUCLOCK:-"1312"}
memclock=${NV_MEMCLOCK:-"877"}

LOCAL_MPIOPTS="--mca btl_openib_warn_default_gid_prefix 0"

# Echo write nodelist
echo "HOSTLIST: $(scontrol show hostname $SLURM_NODELIST | paste -s -d,)" 
echo "" 

echo "Setting Clocks" 
mpirun -np $NNODES -npernode 1 ${LOCAL_MPIOPTS}  ${mpiopts} nvidia-smi -ac ${memclock},${gpuclock} 
echo "" 

## Run HPL
export OMPI_MCA_btl_openib_allow_ib=1

mpirun -np $NPROCS -bind-to none -x LD_LIBRARY_PATH ${LOCAL_MPIOPTS} ${mpiopts} ${HPL_SCRIPTS_DIR}/run_hpl_cuda11.0.sh 2>&1 

## Cleanup Run
cd ${HPL_DIR}


