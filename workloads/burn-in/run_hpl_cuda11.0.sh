#!/bin/bash
#location of HPL 

export HPL_DIR=${HPL_DIR:-$(cd $(dirname $0) && pwd)} # Shared location where all HPL files are stored
export HPL_SCRIPTS_DIR=${HPL_SCRIPTS_DIR:-${HPL_DIR}/} # Shared location where these scripts are stored
export HPL_FILE_DIR=${HPL_FILE_DIR:-${HPL_DIR}/hplfiles} # Shared location where .dat files are stored

CUDAVER=${cudaver:-"11.0"}

CPU_CORES_PER_RANK=${CPU_CORES_PER_RANK:-"4"}

export OMP_NUM_THREADS=$CPU_CORES_PER_RANK
export MKL_NUM_THREADS=$CPU_CORES_PER_RANK
export LD_LIBRARY_PATH=$HPL_DIR:$LD_LIBRARY_PATH

export OMP_PROC_BIND=TRUE
export OMP_PLACES=sockets

export MONITOR_GPU=1

export GPU_TEMP_WARNING=${GPU_TEMP_WARNING:-75}
export GPU_CLOCK_WARNING=${GPU_CLOCK_WARNING:-1300}
export GPU_POWER_WARNING=${GPU_POWER_WARNING:-400}
export GPU_PCIE_GEN_WARNING=${GPU_PCIE_GEN_WARNING:-4}
export GPU_PCIE_WIDTH_WARNING=${GPU_PCIE_WIDTH_WARNING:-16}

export CUDA_DEVICE_MAX_CONNECTIONS=${CUDA_DEVICE_MAX_CONNECTIONS:16}
export TRSM_CUTOFF=${TRSM_CUTOFF:-9000000}
export GPU_DGEMM_SPLIT=${GPU_DGEMM_SPLIT:-"1.0"}

### From MASS
export CUDA_COPY_SPLIT_THRESHOLD_MB=1
export CUDA_DEVICE_MAX_CONNECTIONS=16

# Force AMD CPU optimizations
CPUTYPE=$(cat /proc/cpuinfo | grep vendor_id | head -1 | awk '{print $3}')
if [ ${CPUTYPE} == "AuthenticAMD" ]; then
	export MKL_DEBUG_CPU_TYPE=5
fi

 # Set important UCX optimizations
export UCX_HOME=$(dirname $(dirname $(which ucx_info)))
export UCX_WARN_UNUSED_ENV_VARS=n
export UCX_MEMTYPE_CACHE=n
export UCX_TLS=cma,rc,mm,cuda_copy,cuda_ipc,gdr_copy
export UCX_TLS=cma,rc,mm,cuda_copy,cuda_ipc
export UCX_RNDV_THRESH=16384
export UCX_RNDV_SCHEME=get_zcopy

# 2020-08-05 uncommenting for failing residual checks w. mofed.51 and hpcx2.7
#export UCX_IB_GPU_DIRECT_RDMA=no

export TRSM_CUTOFF=9000000

export MAX_D2H_MS=200
export MAX_H2D_MS=200

export SORT_RANKS=0

#export GRID_STRIPE=8
export RANKS_PER_NODE=8
export RANKS_PER_SOCKET=4

export NUM_PI_BUF=6
export NUM_L2_BUF=6
export NUM_L1_BUF=6
export NUM_WORK_BUF=6

export ICHUNK_SIZE=768
export CHUNK_SIZE=3456

export TEST_SYSTEM_PARAMS=1
export TEST_LOOPS=1

#### Set LRANK for future use
LOCAL_RANK=${OMPI_COMM_WORLD_LOCAL_RANK}
RANK=${OMPI_COMM_WORLD_RANK}

#### Printing xHPL Specific Settings
if [ $LOCAL_RANK == 0 ]; then
        echo ""
        echo "XHPL Settings"
	for V in CPU_CORES_PER_RANK OMP_NUM_THREADS MKL_NUM_THREADS LD_LIBRARY_PATH MONITOR_GPU GPU_TEMP_WARNING GPU_CLOCK_WARNING GPU_POWER_WARNING GPU_PCIE_GEN_WARNING GPU_PCIE_WIDTH_WARNING TRSM_CUTOFF GPU_DGEMM_SPLIT; do
		echo "$V: ${!V}"
	done
	echo ""
fi

#APP=$HPL_DIR/xhpl_cuda-10.0-dyn_mkl-dyn_ompi-1.10.7_gcc4.8.5_9-27-18
#APP=$HPL_DIR/xhpl_cuda-10.0-dyn_mkl-dyn_ompi-3.1.0_gcc4.8.5_9-26-18
#APP=$HPL_DIR/xhpl_cuda-10.0-dyn_mkl-static_ompi-1.10.7_gcc4.8.5_9-27-18
#APP=$HPL_DIR/xhpl_cuda-10.0-dyn_mkl-static_ompi-3.1.0_gcc4.8.5_9-26-18
#APP=$HPL_DIR/xhpl_cuda-10.1-dyn_mkl-dyn_ompi-3.1.3_gcc4.8.5_3-12-19b

#HPLBIN=${HPLBIN:-"${HPL_DIR}/xhpl_cuda-${CUDAVER}-dyn_mkl-static_ompi-3.1.3_gcc4.8.5_3-12-19b"}
HPLBIN=${HPLBIN:-"${HPL_SCRIPTS_DIR}/xhpl_cuda-${CUDAVER}-dyn_mkl-static_ompi-4.0.4_gcc4.8.5_7_23_20"}

if [ ! -f $HPLBIN ]; then
	echo "ERROR: Rank=${RANK} Unable to find executable ${HPLBIN}"
	echo "NOTICE: The HPL binary is not distributed in the repo.  You have to download that separately."
	echo "NOTICE: Please contact your NVIDIA representative for assistance."
	exit 1
fi
if [ ! -x $HPLBIN ]; then
	echo "ERROR: Found HPL binary, but it is not set with the execute bit (${HPLBIN})"
	echo "ERROR: Please set the execute bit (chmod +x ${HPLBIN})"
	exit
fi

export OMPI_MCA_osc=ucx
export OMPI_MCA_btl=^openib,smcuda
export OMPI_MCA_pml=ucx

# Use the bind script to launch
#${HPL_DIR}/bind.sh --ib=single --cpu=exclusive ${HPLBIN}
${HPL_SCRIPTS_DIR}/bind.sh --ib=single --cpu=node ${HPLBIN}


