#!/bin/bash
#location of HPL

export HPL_DIR=$(pwd)

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
	HPLFNDIR=$HPL_DIR/hplfiles
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

	HPLFN=${HPLFNDIR}/HPL.dat_${PxQ}_${SYSTEM}
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

RESULT_FILE=${EXPDIR}/${EXPNAME}.out

echo "" | tee $RESULT_FILE
echo "EXPDIR: ${EXPDIR}" | tee -a $RESULT_FILE
echo "EXPERIMENT NAME: ${EXPNAME}" | tee -a $RESULT_FILE
echo "HPL File: ${HPLFN}" | tee -a $RESULT_FILE
echo "RESULT FILE: ${RESULT_FILE}" | tee -a $RESULT_FILE

echo "" | tee -a $RESULT_FILE
echo "=============================" | tee -a $RESULT_FILE
echo "HPL.dat File" | tee -a $RESULT_FILE
echo "=============================" | tee -a $RESULT_FILE
cat ${HPLFN} | tee -a $RESULT_FILE
echo "=============================" | tee -a $RESULT_FILE
echo "=============================" | tee -a $RESULT_FILE
echo "" | tee -a $RESULT_FILE

### Create working directory in which to work
WORKDIR=${HPL_DIR}/tmp/tmp.${JOBID}
mkdir -p ${WORKDIR} 
if [ $? -ne 0 ]; then
	echo "ERROR: Unable to create working directory $WORKDIR.  Exiting"
	exit
fi

## Create working runtime environment
cp $HPLFN $WORKDIR/HPL.dat
cd $WORKDIR 

#### Confirm mpirun is installed correctly
if [ x"$(which mpirun)" ==  x"" ]; then
	echo "Error, unable to find mpirun.  Installation is broken.  Exiting."
	exit
fi

#### Set Node information
gpuclock=${NV_GPUCLOCK:-"1312"}
memclock=${NV_MEMCLOCK:-"877"}
NVCLOCKS=${memclock},${gpuclock}

# Echo write nodelist
echo "HOSTLIST: $(scontrol show hostname $SLURM_NODELIST | paste -s -d,)" | tee -a $RESULT_FILE
echo "" | tee -a $RESULT_FILE

echo "Setting clocks" | tee -a $RESULT_FILE
LOCAL_MPIOPTS="--mca btl_openib_warn_default_gid_prefix 0"
mpirun -np $NNODES -npernode 1 ${LOCAL_MPIOPTS}  ${mpiopts} nvidia-smi -ac ${NVCLOCKS} | tee -a $RESULT_FILE
echo "" | tee -a $RESULT_FILE

## Run HPL
mpirun -np $NPROCS -bind-to none -x LD_LIBRARY_PATH ${LOCAL_MPIOPTS} ${mpiopts} ${HPL_DIR}/run_hpl_cuda10.1.sh 2>&1 | tee -a $RESULT_FILE

## Cleanup Run
cd ${HPL_DIR}

