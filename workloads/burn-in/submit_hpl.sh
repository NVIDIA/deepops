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

#export PATH=/usr/local/cuda/bin:$PATH
#export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

echo "NVIDIA-SMI:"
nvidia-smi

echo "NUMACTL:"
numactl --show

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

if [ x"${CONT}" = x"" ]; then
	echo "ERROR: container is not defined at CONT."
	exit 1
fi

if [ x"${SYSCFGVAR}" == x"" ]; then
	echo "ERROR: SYSCFGVAR must be defined. Exiting."
	exit 1
fi

if [ x"${GPUMEM}" == x"" ]; then
	echo "ERROR: GPUMEM not set. Exiting"
	exit
fi

if [ x"${CRUNTIME}" == x"" ]; then
	echo "ERROR: CRUNTIME not set. Exiting"
	exit
fi

# EXPDIR should already be created with the correct files
if [ x"${EXPDIR}" == x"" ]; then
	echo "ERROR: EXPDIR is not defined.  Exiting."
	exit 1
fi

echo "" 
echo "=============================" 
echo "HPL.dat File" 
echo "=============================" 
cat HPL.dat
echo "=============================" 
echo "=============================" 
echo "" 

#### Set Node information
gpuclock=${NV_GPUCLOCK:-"1312"}
memclock=${NV_MEMCLOCK:-"877"}

LOCAL_MPIOPTS="--mca btl_openib_warn_default_gid_prefix 0"

export TEST_LOOPS=1
export TEST_SYSTEM_PARAMS=1


# Echo write nodelist
echo "HOSTLIST: $(scontrol show hostname $SLURM_NODELIST | paste -s -d,)" 
echo "" 

## Run HPL
####mpirun -np $NPROCS -bind-to none -x LD_LIBRARY_PATH ${LOCAL_MPIOPTS} ${mpiopts} ${HPL_SCRIPTS_DIR}/run_hpl_cuda11.0.sh 2>&1 

if [ -f $SYSCFGVAR ]; then
	if [ x"${CRUNTIME}" != x"baremetal" ]; then
	        SYSCFGDIR="/datfiles/"
	fi
fi


# Set the mount as the temporary directory
MOUNT=$(pwd):/datfiles

case ${CRUNTIME} in
	enroot)
		CMD="srun --mpi=pmi2 -N ${NNODES} --ntasks-per-node=${GPUS_PER_NODE} \
                     --container-image="${CONT}" --container-mounts="${MOUNT}" \
		     /workspace/hpl.sh --config ${SYSCFGDIR}${SYSCFGVAR} --dat /datfiles/HPL.dat" ;;
	singularity)
		CMD="srun --mpi=pmi2 -N ${NNODES} --ntasks-per-node=${GPUS_PER_NODE} \
		     singularity run --nv -B "${MOUNT}" "${CONT}" \
		     /workspace/hpl.sh --config ${SYSCFGDIR}${SYSCFGVAR} --dat /datfiles/HPL.dat" ;;
	baremetal)
		#CMD="mpirun -np $NPROCS -bind-to none -x LD_LIBRARY_PATH ${LOCAL_MPIOPTS} ${mpiopts} ${HPL_SCRIPTS_DIR}/hpl.sh" 
		echo "baremetal not supported yet"
		exit 1
		CMD="srun --mpi=pmi2 -N ${NNODES} --ntasks-per-node=${GPUS_PER_NODE} \
		     ./hpl.sh --config ${SYSCFGVAR} --dat ./HPL.dat" 
		;;
	*)
		echo "ERROR: Runtime ${CRUNTIME} not supported.  Exiting"
		exit 1
		;;
esac

echo $CMD
$CMD


## Cleanup Run
cd ${HPL_DIR}


