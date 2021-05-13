GPU_AFFINITY="0:1:2:3:4:5:6:7:8:9:16:11:12:13:14:15"
CPU_AFFINITY="0-2:3-5:6-8:9-11:12-14:15-17:18-20:21-23:24-26:27-29:30-32:33-35:36-38:39-41:42-44:45-47"
CPU_CORES_PER_RANK=3
MEM_AFFINITY="0:0:0:0:0:0:0:01:1:1:1:1:1:1:1:1"
UCX_AFFINITY="mlx5_1:mlx5_1:mlx5_2:mlx5_2:mlx5_3:mlx5_3:mlx5_4:mlx5_4:mlx5_7:mlx5_7:mlx5_8:mlx5_8:mlx5_9:mlx5_9:mlx5_10:mlx_10"
GPU_CLOCK="877,1275"

export MONITOR_GPU=1
export TEST_SYSTEM_PARAMS=1
export TEST_LOOPS=1
export GPU_CLOCK_WARNING=$(echo ${GPU_CLOCK} | cut -f2 -d,)
export GPU_POWER_WARNING=350
export GPU_PCIE_GEN_WARNING=3
export GPU_PCIE_WIDTH_WARNING=16

## Depending on driver version, you may need to uncomment the following line
# export LD_LIBRARY_PATH="/usr/local/cuda/compat:$LD_LIBRARY_PATH

