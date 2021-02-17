#!/bin/bash
set -euo pipefail

print_usage() {
    cat << EOF
${0} [options] [--] COMMAND [ARG...]

Control binding policy for each task. Assumes one rank will be launched for each GPU.

Options:
    --cpu=MODE
        * exclusive -- bind each rank to an exclusive set of cores near its GPU
        * node -- bind each rank to all cores in the NUMA node nearest its GPU [default]
        * off -- don't bind
    --mem=MODE
        * node -- bind each rank to the nearest NUMA node [default]
        * off -- don't bind
    --ib=MODE
        * single -- bind each rank to a single IB device near its GPU
        * off -- don't bind [default]
    --cluster=CLUSTER
        Select which cluster is being used. May be required if system params cannot be detected.
EOF
}

################################################################################
# Argument parsing
################################################################################

cpu_mode='node'
mem_mode='node'
ib_mode='off'
cluster='selene'
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) print_usage ; exit 0 ;;
        --cpu=*) cpu_mode="${1/*=/}"; shift ;;
        --cpu)   cpu_mode="$2"; shift 2 ;;
        --mem=*) mem_mode="${1/*=/}"; shift ;;
        --mem)   mem_mode="$2"; shift 2 ;;
        --ib=*) ib_mode="${1/*=/}"; shift ;;
        --ib)   ib_mode="$2"; shift 2 ;;
        --cluster=*) cluster="${1/*=/}"; shift ;;
        --cluster)   cluster="$2"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done
if [ $# -lt 1 ]; then
    echo 'ERROR: no command given' 2>&1
    print_usage
    exit 1
fi

################################################################################
# Get system params
################################################################################

# LOCAL_RANK is set with an enroot hook for Pytorch containers
# SLURM_LOCALID is set by Slurm
# OMPI_COMM_WORLD_LOCAL_RANK is set by mpirun

readonly local_rank="${LOCAL_RANK:=${OMPI_COMM_WORLD_LOCAL_RANK}}"

if [ -z "${local_rank}" ]; then
    echo 'ERROR: cannot read LOCAL_RANK from env' >&2
    exit 1
fi

num_gpus=$(nvidia-smi -i 0 --query-gpu=count --format=csv,noheader,nounits)
if [ "${local_rank}" -ge "${num_gpus}" ]; then
    echo "ERROR: local rank is ${local_rank}, but there are only ${num_gpus} gpus available" >&2
    exit 1
fi

# Check to see if HW_HCALIST or HW_CORELIST are defined.  If so
# validate the output to ensure they have the right format

if [[ -v HW_HCALIST ]]; then
	hw_hcacnt=$(echo ${HW_HCALIST} | sed 's/:/ /g' | wc -w)
	if [ ${hw_hcacnt} -ne ${num_gpus} ]; then
		echo ""
		echo "ERROR: HW_HCALIST is defined, but the number of items defined <${hw_hcacnt}>"
		echo "ERROR: does not match the number of gpus found <${num_gpus}>".
		echo "ERROR: Exiting"
		echo ""
		exit 1
        else	
		echo "Using defined HW_HCALIST: ${HW_HCALIST}"
	fi
fi

if [ -v HW_CORELIST ]; then
	hw_corcent=$(echo ${HW_CORELIST} | sed 's/:/ /g' | wc -w)
	if [ ${hw_corecnt} -ne ${num_gpus} ]; then
		echo ""
		echo "ERROR: HW_CORELIST is defined, but the number of items defined <$hw_corecnt>"
		echo "ERROR: does not match the number of gpus found <${num_gpus}>".
		echo "ERROR: Exiting"
		echo ""
		exit 1
        else	
		echo "Using defined HW_COREIST: ${HW_CORELIST}"
	fi
fi

get_lscpu_value() {
    awk -F: "(\$1 == \"${1}\"){gsub(/ /, \"\", \$2); print \$2; found=1} END{exit found!=1}"
}

lscpu_out=$(lscpu)
num_sockets=$(get_lscpu_value 'Socket(s)' <<< "${lscpu_out}")
num_nodes=$(get_lscpu_value 'NUMA node(s)' <<< "${lscpu_out}")
cores_per_socket=$(get_lscpu_value 'Core(s) per socket' <<< "${lscpu_out}")

# Grab affinity information from nvidia-smi
nvtopofn=/tmp/nvtopofn.$$
nvidia-smi topo -m | tr '\t' ' ' > ${nvtopofn}

## Grab Headers
### echo output -> grab top line -> remove ansi codes -> remove leading trainly whitespace and change to comma-delimiated
### Note, any header that has white space "CPU AFFINITY", isnt going to be processed correctly.  We can deal with this
### later
hditems=($(cat ${nvtopofn} | head -1 | sed 's/\x1b\[[0-9;]*m//g'))

## Find affinity between all gpus and network devices
for gpuid in $local_rank; do
	gpudev="GPU${gpuid}"
	#Verify the GPUs are numbered consistently
	if [ $(cat ${nvtopofn} | grep -wE "^${gpudev}" | wc -l) -ne 1 ]; then
		echo "ERROR, unable to find single instance of ${gpudev}.  Exiting." 1>&2
		echo "GPU Information:" 1>&2
		cat ${nvtopofn} | grep -E "^GPU" 1>&2
		exit 1
	fi
        # For each GPU, find the CPU Affinity, be smart about the column as the format changes
        if [ $(cat ${nvtopofn} | grep "NUMA Affinity" | wc -l) -gt 0 ]; then
	        cpulist=$(grep -E "^${gpudev} " ${nvtopofn} | awk '{print $(NF-1)}')
	else
	        cpulist=$(grep -E "^${gpudev} " ${nvtopofn} | awk '{print $(NF)}')
	fi
	if [ x"${cpulist}" == x"" ]; then
		echo "ERROR: Unable to find a CPUList for ${gpudev}. Exiting." 1>&2
		echo "--------------------" 1>&2
		echo ${nvtopo}  1>&2
		echo "--------------------" 1>&2
		exit 1
	fi
       
	# Lookup cpunode
	cpunode=$(numactl --physcpubind=${cpulist} numactl --show | grep nodebind: | cut -f2- -d" " | sed 's/ $//g')
	if [ $(echo $cpunode | wc -l) -ne 1 ]; then
		echo "ERROR: The node binding for ${gpudev} is not exactly one node.  Exiting"
		numactl --physcpubind=${cpulist} numactl --show
		exit 1
	fi

	## This is an AMD, NPS=4 Hack
	curnps=$(lscpu |grep "NUMA node(s)"|awk '{print $3 / 2}')

	if [ $curnps -eq 4 ]; then
    		if [ $(( local_rank % 2 )) == 0 ]; then
                       cpunode=$(( cpunode - 1 ))
		fi
	fi

	# for now assume memnode is cpunode
        memnode=$cpunode

	# Search for devices, only ib_mode is not off
	
	if [ x"${ib_mode}" != x"off" ]; then
		# Should we autodetect, or use the provided list
		if [[ ! -v HW_HCALIST ]]; then
        		devitems=($(cat ${nvtopofn} | grep -wE "${gpudev}" | tail -1 | sed 's/\x1b\[[0-9;]*m//g'))
        		pixlist=()
			pxblist=()
        		phblist=()
	        	for ((i=0; i<${#devitems[@]}; ++i)); do
	        		if [ "${devitems[$i]}" == "PIX" ]; then
	        			pixlist+=(${hditems[$(( i - 1 ))]})
	        		fi
	        		if [ "${devitems[$i]}" == "PHB" ]; then
	        			phblist+=(${hditems[$(( i - 1 ))]})
	        		fi
	        		if [ "${devitems[$i]}" == "PXB" ]; then
	        			pxblist+=(${hditems[$(( i - 1 ))]})
	        		fi
        		done
        		if [ ${#pixlist[@]} -eq 0 ]; then
        			if [ ${#pxblist[@]} -eq 0 ]; then
        				echo "WARNING: No HCA near GPU on same root complex, disabling HCA Affinity."
					ib_mode="off"
					node_map_mlx=()
				else
					hcalist=(${pxblist[@]})
				fi
			else
    				hcalist=(${pixlist[@]})
			fi
		else
			# MAP using from the provided list
			p=$(( local_rank + 1 ))
			hcalist=($(echo ${HW_HCALIST} | cut -f${p} -d:))
			echo "Manually using ${hcalist[@]} for $local_rank"
		fi
	fi
	
        # Add devices to map array
	if [ x"${ib_mode}" != x"off" ]; then
		if [[ -v HW_HCALIST ]]; then
			node_map_mlx=${hcalist[0]}
		else
  		    i=0
		    # This could be done much better, consider all curnps values, support multi-rail per GPU, etc
		    if [ $curnps -eq 4 ]; then 
			i=$(( local_rank % 2 ))
		    fi	
        	    node_map_mlx=${hcalist[i]}
	        fi
	fi
	node_map_cpunode=${cpunode}
	node_map_mem=${memnode}
	node_map_physcpu=${cpulist}
done

readonly cores_per_node=$(( (num_sockets * cores_per_socket) / num_nodes ))
if [ ${num_gpus} -gt 1 ]; then
    readonly gpus_per_node=$(( num_gpus / num_nodes ))
else
    readonly gpus_per_node=1
fi

readonly cores_per_gpu=$(( cores_per_node / gpus_per_node ))
readonly local_node=$(( local_rank / gpus_per_node ))

echo "num_sockets=${num_sockets} num_nodes=${num_nodes} cores_per_socket=${cores_per_socket} local_node=${local_node}"

################################################################################
# Setup for exec
################################################################################

declare -a numactl_args=()

case "${cpu_mode}" in
    exclusive)
	numactl_args+=( "--physcpubind=${node_map_physcpu}" )
        ;;
    node)
	numactl_args+=( "--cpunodebind=${node_map_cpunode}" )
        ;;
    off|'')
        ;;
    *)
        echo "ERROR: invalid cpu mode '${cpu_mode}'" 2>&1
        print_usage
        exit 1
        ;;
esac

case "${mem_mode}" in
    node)
	numactl_args+=( "--membind=${node_map_mem}" )
        ;;
    off|'')
        ;;
    *)
        echo "ERROR: invalid mem mode '${mem_mode}'" 2>&1
        print_usage
        exit 1
        ;;
esac

case "${ib_mode}" in
    single)
	export OMPI_MCA_btl_openib_if_include=${node_map_mlx}
        ;;
    off|'')
	export OMPI_MCA_btl_openib_if_include=""
        ;;
    *)
        echo "ERROR: invalid ib mode '${ib_mode}'" 2>&1
        print_usage
        exit 1
        ;;
esac

################################################################################
# Exec
################################################################################

# Is this a GPUDirect aware binary or not
export CUDA_VISIBLE_DEVICES=${local_rank}

echo "MAP: rank=${OMPI_COMM_WORLD_RANK} lrank=$local_rank HCA=${OMPI_MCA_btl_openib_if_include} CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES} numactl_args=\"${numactl_args[@]}\" hplbin=${@}"

#export OMPI_MCA_btl_openib_allow_ib=1
export UCX_NET_DEVICES=${OMPI_MCA_btl_openib_if_include}:1

if [ "${#numactl_args[@]}" -gt 0 ] ; then
    exec numactl "${numactl_args[@]}" -- "${@}"
else
    exec "${@}"
fi



