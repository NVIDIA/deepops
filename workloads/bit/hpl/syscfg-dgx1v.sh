GPU_AFFINITY="0:1:2:3:4:5:6:7"
CPU_AFFINITY="0-4:5-9:10-14:15-19:20-24:25-29:30-34:35-39"
CPU_CORES_PER_RANK=4
MEM_AFFINITY="0:0:0:0:1:1:1:1"
UCX_AFFINITY="mlx5_0:mlx5_0:mlx5_1:mlx5_1:mlx5_2:mlx5_2:mlx5_3:mlx5_3"
GPU_CLOCK="877,1275"

export MONITOR_GPU=1
export TEST_SYSTEM_PARAMS=1
export TEST_LOOPS=1
export GPU_CLOCK_WARNING=$(echo ${GPU_CLOCK} | cut -f2 -d,)
export GPU_POWER_WARNING=300
export GPU_PCIE_GEN_WARNING=3
export GPU_PCIE_WIDTH_WARNING=16

## Depending on driver version, you may need to uncomment the following line
# export LD_LIBRARY_PATH="/usr/local/cuda/compat:$LD_LIBRARY_PATH

export UCX_TLS=all
export OMPI_MCA_pml_ucx_verbose=100
