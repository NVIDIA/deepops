#!/bin/bash
#location of HPL 

export HPL_DIR=${HPL_DIR:-$(pwd)}

CUDAVER=${cudaver:-"10.1"}

CPU_CORES_PER_RANK=${CPU_CORES_PER_RANK:-"4"}

export OMP_NUM_THREADS=$CPU_CORES_PER_RANK
export MKL_NUM_THREADS=$CPU_CORES_PER_RANK
export LD_LIBRARY_PATH=$HPL_DIR:$LD_LIBRARY_PATH

export MONITOR_GPU=1
export GPU_TEMP_WARNING=${GPU_TEMP_WARNING:-75}
export GPU_CLOCK_WARNING=${GPU_CLOCK_WARNING:-1312}
export GPU_POWER_WARNING=${GPU_POWER_PWARNING:-300}
export GPU_PCIE_GEN_WARNING=${GPU_PCIE_GEN_WARNING:-3}
export GPU_PCIE_WIDTH_WARNING=${GPU_PCIE_WIDTH_WARNING:-16}

#export CUDA_DEVICE_MAX_CONNECTIONS=${CUDA_DEVICE_MAX_CONNECTIONS:16}
#export TRSM_CUTOFF=16000
export TRSM_CUTOFF=${TRSM_CUTOFF:-1000000}
#export GPU_DGEMM_SPLIT=1.00
export GPU_DGEMM_SPLIT=${GPU_DGEMM_SPLIT:-"1.0"}
#export RANK_PERF=1100.0
#export CHECK_CPU_DGEMM_PERF=0
#export CPU_DGEMM_PERF_WARNING=1000.0

#export TEST_SYSTEM_PARAMS=0
#export TEST_LOOPS=10

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

HPLBIN=${HPLBIN:-"${HPL_DIR}/xhpl_cuda-${CUDAVER}-dyn_mkl-static_ompi-3.1.3_gcc4.8.5_3-12-19b"}

if [ ! -x $HPLBIN ]; then
	echo "ERROR: Rank=${RANK} Unable to find executeable ${HPLBIN}"
	exit 1
fi

# Use the bind script to launch
${HPL_DIR}/bind.sh --ib=single --cpu=exclusive ${HPLBIN}
