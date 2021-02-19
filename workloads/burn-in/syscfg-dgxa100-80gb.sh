CPU_AFFINITY="32-47:48-63:0-15:16-31:96-111:112-127:64-79:80-95"
CPU_CORES_PER_RANK=16
GPU_AFFINITY="0:1:2:3:4:5:6:7"
MEM_AFFINITY="2:3:0:1:6:7:4:5"
UCX_AFFINITY="mlx5_0:mlx5_1:mlx5_2:mlx5_3:mlx5_6:mlx5_7:mlx5_8:mlx5_9"
GPU_CLOCK="1593,1275"

export MONITOR_GPU=1
export TEST_SYSTEM_PARAMS=1
export TEST_LOOPS=1
export GPU_CLOCK_WARNING=1275
export GPU_POWER_WARNING=400
export GPU_PCIE_GEN_WARNING=4
export GPU_PCIE_WIDTH_WARNING=16

## Depending on driver version, you may need to uncomment the following line
# export LD_LIBRARY_PATH="/usr/local/cuda/compat:$LD_LIBRARY_PATH

