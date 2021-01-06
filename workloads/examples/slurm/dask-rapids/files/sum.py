# pylint: disable-all
import os, sys, argparse, time
import cupy
import dask
import dask.array as da
from dask_cuda import LocalCUDACluster
from dask.distributed import Client, LocalCluster, wait
from dask.delayed import delayed
from dask.diagnostics import ProgressBar
from multiprocessing.pool import ThreadPool
import socket

def create_data(rs, xdim, ydim, x_chunk_size, y_chunk_size):
    x = rs.normal(10, 1, size=(xdim, ydim), chunks=(x_chunk_size, y_chunk_size))
    return x

def run(data):
    (data + 1)[::2, ::2].sum().compute()
    return

def get_scheduler_info():
    scheduler_hostname = socket.gethostname()
    scheduler_ip = socket.gethostbyname(scheduler_hostname)
    scheduler_port = '8786'
    scheduler_uri = str(scheduler_ip) + ':' +  scheduler_port
    return(scheduler_ip, scheduler_uri)

def main():

    parser = argparse.ArgumentParser()
    parser.add_argument('--xdim', type=int, default=500000)
    parser.add_argument('--ydim', type=int, default=500000)
    parser.add_argument('--x_chunk_size', type=int, default=10000)
    parser.add_argument('--y_chunk_size', type=int, default=10000)
    parser.add_argument('--use_gpus_only', action="store_true")
    parser.add_argument('--n_gpus', type=int, default=1)
    parser.add_argument('--use_cpus_only', action="store_true")
    parser.add_argument('--n_cpu_sockets', type=int, default=1)
    parser.add_argument('--n_cpu_cores_per_socket', type=int, default=1)
    parser.add_argument('--use_distributed_dask', action="store_true")
    args = parser.parse_args()

    sched_ip, sched_uri = get_scheduler_info()

    if args.use_distributed_dask:
        print('Using Distributed Dask')
        client = Client(sched_uri)
    elif args.use_gpus_only:
        print('Using GPUs and Local Dask')
        cluster = LocalCUDACluster(ip=sched_ip, n_workers=args.n_gpus)
        client = Client(cluster)
    elif args.use_cpus_only:
        print('Using CPUs and Local Dask')
        cluster = LocalCluster(ip=sched_ip, n_workers=args.n_cpu_sockets, threads_per_worker=args.n_cpu_cores_per_socket)
        client = Client(cluster)
    else:
        print("Exiting...")
        sys.exit(-1)
        
    start = time.time()
    if args.use_gpus_only:
        print('Allocating and initializing arrays using GPU memory with CuPY')
        rs = da.random.RandomState(RandomState=cupy.random.RandomState)
    elif args.use_cpus_only:
        print('Allocating and initializing arrays using CPU memory')
        rs = da.random.RandomState()
    x = create_data(rs, args.xdim, args.ydim, args.x_chunk_size, args.y_chunk_size)
    print('Array size: {:.2f} TB.  Computing parallel sum . . .'.format(x.nbytes/1e12))
    run(x)
    end = time.time()
    delta = (end - start)

    print('Processing complete.')
    print('Wall time create data + computation time: {:10.8f} seconds'.format(delta))

    del x

if __name__ == '__main__':
    main()
