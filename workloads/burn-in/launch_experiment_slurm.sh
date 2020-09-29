#!/bin/bash
#
# Launch a HPL Burn-in test based.
#
# ./launch_experiment_slurm.sh <nodes per job>
#
# - Right now systems supported are dgx1v_16G, dgx1v_32G, dgx2, and dgxa100
# - Eventually the code should (somewhat) support generic systems.
#
# -- Requirements
# - OpenMPI 4.0.4 and UCX 1.9 must be on the PATH and LD_LIBRARY_PATH
# - The correct cuda version should be installed and on the PATH and LD_LIBRARY_PATH
# - run the install_hplbit_deps.sh script to do the above.
# - Slurm Cluster Manager setup with PMIx and hwloc is required.
#  
#

### TODO:
### - Add a loop at the end that tracks the jobs
###   <TIME> TotalJobs:<TOTALJOBS> RunningJobs:<RunningJobs> CompletedJobs:<CompJobs> QueuedJobs:<Queued>
###
###    When all the jobs are down, run the verify script, put the results in the results directory
### - Set the full expdir from this script

export HPL_DIR=${HPL_DIR:-$(cd $(dirname $0) && pwd)} # The shared directory where scripts, data, and results are stored
export HPL_SCRIPTS_DIR=${HPL_SCRIPTS_DIR:-${HPL_DIR}} # The shared directory where these scripts are stored

## Set default options
niters=5
cudaver=11.0
partition=batch
usehca=0
usegres=1
maxnodes=9999
mpiopts=""
walltime=02:00:00
verbose=0
ORDER_CMD="cat"

print_usage() {
   cat << EOF

${0} [options]

Launch an HPL Burnin test.

Required Options:
    -s|--sys <SYSTEM>
        * Set to the system type on which to run.  Ex: dgx1v_16G, dgx1v_32G, dgx2, dgx2h, dgxa100, generic
    -c|--count <Count>
        * Set to the number of nodes to use per job

Other Options:
    -i|--iters <Iterations>
        * Set to the number of iterations per experiment.  Default is ${niters}."
    --cudaver <CUDA Version>
        * Set the version of CUDA to use.  Default is ${cudaver}."
    -p|--part <Slurm Partition>
        * Set the Slurm partition to use.  Default is ${partition}."
    -a|--account <Slurm Account>
        * Set the Slurm accoutn to use.  Default is None."
    --usehca <Use HCA Affinity>
        * Use HCA affinity. Set to 1 to enable.  Default is ${usehca}."    
    --maxnodes <Number_of_nodes>
        * Set the maximum number of nodes to use per experiment.  This is used for testing.  Default is all of them."
    --mpiopts <Options>
        * Sets string with additional OpenMPI options to pass to mpirun.  Default is none.
    --usegres <Val>
	* Enable/disable use of GRES options in Slurm (1/0).  Default is ${usegres}.
    --gpuclock MHz
        * Set specific clock to use during run.  Default is to set the clocks to maximum.
    --memclock MHz
        * Set specific clock to use during run.  Default is to set the clocks to maximum.
    -r|--random
        * Randomize which nodes get used each iteration
    -v|--verbose
        * Provide extra logging information
    --hpldat <FILE>
        * Use a specific HPL.dat file for the experiment.  The P and Q values in the file will be used and override the -c option.

EOF

exit
}

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help) print_usage ; exit 0 ;;
		-s|--sys) system="$2"; shift 2 ;;
		-c|--count) nodes_per_job="$2"; shift 2 ;;
		-i|--iters) niters="$2"; shift 2 ;;
		--cudaver) cudaver="$2"; shift 2 ;;
		-p|--part) partition="$2"; shift 2 ;;
		-a|--account) account="-A $2"; shift 2 ;;
		-t|--walltime) walltime="$2"; shift 2 ;;
		-r|--random) ORDER_CMD=shuf; shift 1;;
		-v|--verbose) verbose=1; shift 1;;
		--usehca) usehca="$2"; shift 2;;
	        --maxnodes) maxnodes="$2"; shift 2 ;;	
		--mpiopts) mpiopts="$2"; shift 2 ;;
		--usegres) usegres="$2"; shift 2 ;;
		--gpuclock) gpuclock="$2" ; shift 2 ;;
		--memclock) memclock="$2" ; shift 2 ;;
		--hpldat) hpldat="$2"; shift 2 ;;
		*) echo "Option <$1> Not understood" ; exit 1 ;;

        esac
done

if [ x"${system}" == x"" ]; then
	echo "ERROR: System must be set."
	print_usage
fi

if [ x"${nodes_per_job}" == x"" ]; then
	echo "ERROR: Number of nodes per job (-c) must be set."
	print_usage
fi

if [ x"${system}" == x"dgx1v_16G" ]; then
	export gpus_per_node=8
	export NV_GPUCLOCK=1530
	export NV_MEMCLOCK=877
elif [ x"${system}" == x"dgx1v_32G" ]; then
	export gpus_per_node=8
	export NV_GPUCLOCK=1530
	export NV_MEMCLOCK=877
elif [ x"${system}" == x"dgx2" ]; then
	export gpus_per_node=16
	export NV_GPUCLOCK=1530
	export NV_MEMCLOCK=877
elif [ x"${system}" == x"dgx2h" ]; then
	echo "ERROR: DGX-2H is not supported yet.  Exiting"
	export gpus_per_node=16
	export NV_GPUCLOCK=1530
	export NV_MEMCLOCK=877
	exit
elif [ x"${system}" == x"dgxa100" ]; then
	export gpus_per_node=8
	export NV_GPUCLOCK=1275
	export NV_MEMCLOCK=1215
	export GPU_CLOCK_WARNING=1335 
	export GPU_POWER_WARNING=400 
	export GPU_PCIE_GEN_WARNING=4
        export CPU_CORES_PER_RANK=16
elif [ x"${system}" == x"workshop" ]; then
	export gpus_per_node=1
	export NV_GPUCLOCK=1530
	export NV_MEMCLOCK=877
	export hpldat="${HPL_SCRIPTS_DIR}/hplfiles/HPL.dat_1x1_workshop_16G"
	echo "WARN; Running in non-performant workshop configuration"
else
	echo "ERROR: Generic systems are not supported yet."
	exit
fi

if [ x"${usegres}" == x"1" ]; then
	gresstr="--gpus-per-node ${gpus_per_node}"
fi

if [ x"${gpuclock}" != x"" ]; then
	NV_GPUCLOCK=${gpuclock}
fi
if [ x"${memclock}" != x"" ]; then
	NV_MEMCLOCK=${memclock}
fi

if [ x"${hpldat}" != x"" ]; then
	echo ""
	echo "An HPL.dat file has been manually specified."
	if [ ! -f ${hpldat} ]; then
		echo "ERROR: HPL.dat file specified, but not found.  ${hpldat}"
		exit 1
	fi
	# Line 10 is Number of PQ pairs, line 11 is P, line 12 is Q
	NPQ=$(cat ${hpldat} | tail +10 | head -1 | awk '{print $1}')
	P=$(cat ${hpldat} | tail +11 | head -1 | awk '{print $1}')
	Q=$(cat ${hpldat} | tail +12 | head -1 | awk '{print $1}')
	if [ ${NPQ} -ne 1 ]; then
		echo "WARNING: Node allocation is only going to match the first P*Q pair"
	fi

	nodes_per_job=$(( P * Q / gpus_per_node ))
	echo "Overriding nodes_per_job, using nodes_per_job=${nodes_per_job} to match settings in ${hpldat}"
	echo ""
	export HPLDAT=${hpldat}
fi

export SYSTEM=${system}
export GPUS_PER_NODE=${gpus_per_node}

RUNSCRIPT=${HPL_SCRIPTS_DIR}/submit_hpl_cuda${cudaver}.sh

# Set a name for the experiment
export EXPNAME=${nodes_per_job}node_${system}_$(date +%Y%m%d%H%M%S)
export EXPDIR=$(pwd)/results/${EXPNAME}

if [ -d $EXPDIR ]; then
	echo "ERROR: Directory already exists: $EXPDIR"
	exit 1
fi
mkdir -p $EXPDIR

# Grab nodelist and node count from the batch queue
export NODELIST=$(sinfo -p ${partition} | grep ${partition} | grep " idle " | awk '{print $6}')

export MACHINEFILE=/tmp/mfile.$$
scontrol show hostname ${NODELIST} | head -${maxnodes} > $MACHINEFILE
export total_nodes=$(cat $MACHINEFILE | wc -l)

if [ $total_nodes -eq 0 ]; then
	echo "ERROR: Unable to find any idle nodes in partition=${partition}.  Exiting."
	echo ""
	exit 1
fi


### Report all variables
echo ""
echo "Experiment Variables:"
for V in HPL_DIR HPL_SCRIPTS_DIR EXPDIR system nodes_per_job gpus_per_node gpuclock memclock  niters cudaver partition usehca maxnodes mpiopts gresstr total_nodes hpldat; do
	echo -n "${V}: "
        if [ x"${!V}" != x"" ]; then	
        	echo "${!V}"
	else
		echo "<Not Set>"
	fi
done
echo ""

jobid_list=()

# Define hostfile for each iteration
HFILE=/tmp/hfile.$$

for N in $(seq ${niters}); do
	echo "Starting Iteration $N"
	P=1
	cat $MACHINEFILE | ${ORDER_CMD} > $HFILE
	while [ $(( P + nodes_per_job - 1 ))  -le ${total_nodes} ]; do
		# Create hostlist per iter
		HLIST=$(scontrol show hostlist $(tail +$P ${HFILE} | head -${nodes_per_job} | sort | paste -d, -s))
		CMD="sbatch -N ${nodes_per_job} --time=${walltime} ${account}  -p ${partition} --parsable --ntasks-per-node=${gpus_per_node} ${gresstr} --export ALL,EXPDIR,NV_GPUCLOCK,NV_MEMCLOCK,HPLDAT,SYSTEM,GPUS_PER_NODE,CPU_CORES_PER_RANK --exclusive -o ${EXPDIR}/${EXPNAME}-%j.out -w ${HLIST} ${RUNSCRIPT}"
		if [ ${verbose} -eq 1 ]; then
		        echo "Submitting:  $CMD"
		fi
  		jobid=$($CMD) 
		if [ $? -ne 0 ]; then
			echo "ERROR: Unable to submit job.  Err=$?"
			# Cleanup experiment
			#exit $? 
		fi
		jobid_list+=($jobid)

		P=$(( $P + $nodes_per_job ))
	done
	if [ $(( P - 1 )) -lt ${total_nodes} ]; then
	        # Print out the extra nodes not used
	        HLIST=$(scontrol show hostlist $(tail +$P ${HFILE} | sort | paste -d, -s))
	        echo ""
	        echo "Unused nodes for this iteration: ${HLIST}"
        fi
	echo ""
	echo "Ending Iteration $N"
done

wait

rm ${HFILE}
rm ${MACHINEFILE}

# Now watch and wait on the experimet
# Group jobs into running, waiting

total_jobs=${#jobid_list[@]}
SQUEUEFN=/tmp/squeue.data.$$

jobs_tbd=1
p=0
display_row=25

while [ ${jobs_tbd} != 0 ]; do
	if [ $(( p % display_row )) == 0 ]; then
		echo ""
		echo "             Date                   TotalJobs RunningJobs  WaitingJobs FinishingJobs"
		echo "------------------------------------------------------------------------------------"
        fi
	squeue -a | grep -E $(echo ${jobid_list[@]} | tr ' ' '|') > $SQUEUEFN
        jobs_tbd=$(cat $SQUEUEFN | wc -l)
	c_running=$(cat $SQUEUEFN | grep " R " | wc -l)
	c_waiting=$(cat $SQUEUEFN | grep " PD " | wc -l)
        c_finishing=$(cat $SQUEUEFN | grep " CG " | wc -l)
	echo -n "$(date)::"
	echo ${total_jobs} ${c_running} ${c_waiting} ${c_finishing} | awk '{printf("%12d %12d %12d %12d\n",$1,$2,$3,$4);}'
	if [ ${jobs_tbd} != 0 ]; then
		sleep 10
	fi
	p=$(( p + 1 ))
done

echo ""

echo "===================="
echo "Experiment completed"
echo "===================="

VLOGFN=${EXPDIR}/verify_results.txt

./verify_hpl_experiment.py ${EXPDIR} | tee ${VLOGFN}

echo "Run Summary:"
echo "Experiment Results Directory: ${EXPDIR}"
echo "Total Nodes: ${total_nodes}"
echo "Nodes Per Job:: ${nodes_per_job}"
echo "Verify Log: ${VLOGFN}"

echo ""
echo "To rerun the verification: ${HPL_SCRIPTS_DIR}/verify_hpl_experiment.py ${EXPDIR}"
echo ""



