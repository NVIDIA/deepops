#!/bin/bash
#
# Launch a HPL burnin test based.
#
# ./launch_experiment_slurm.sh <nodes per job>
#
# - Right now systems supported are dgx1v_16G, dgx1v_32G, and dgx2.
# - dgxa100 will be added when its read.
# - Eventually the code should (somewhat) support generic systems.
#
# -- Requirements
# - OpenMPI 3.1.X must be on the PATH and LD_LIBRARY_PATH
# - The correct cuda version should be installed and on the PATH and LD_LIBRARY_PATH
# - Slurm is required.
#

### TODO:
### - Add a loop at the end that tracks the jobs
###   <TIME> TotalJobs:<TOTALJOBS> RunningJobs:<RunningJobs> CompletedJobs:<CompJobs> QueuedJobs:<Queued>
###
###    When all the jobs are down, run the verify script, put the results in the results directory
### - Set the full expdir from this script

## Set default options
niters=5
cudaver=10.1
partition=batch
usehca=0
usegres=1
maxnodes=9999
mpiopts=""
walltime=00:30:00

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
    --cudaver=<CUDA Version>
        * Set the version of CUDA to use.  Default is ${cudaver}."
    -p|--part=<Slurm Partition>
        * Set the Slurm partition to use.  Default is ${partition}."
    --usehca=<Use HCA Affinity>
        * Use HCA affinity. Set to 1 to enable.  Default is ${usehca}."    
    --maxnodes=<Number_of_nodes>
        * Set the maximum number of nodes to use per experiment.  This is used for testing.  Default is all of them."
    --mpiopts=<Options>
        * Sets string with additional OpenMPI options to pass to mpirun.  Default is none.
    --usegres=<Val>
	* Enable/disable use of GRES options in Slurm (1/0).  Default is ${usegres}.
    --gpuclock=MHz
        * Set specific clock to use during run.  Default is to set the clocks to maximum.
    --memclock=MHz
        * Set specific clock to use during run.  Default is to set the clocks to maximum.
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
		--usehca) usehca="$2"; shift 2;;
	        --maxnodes) maxnodes="$2"; shift 2 ;;	
		--mpiopts) mpiopts="$2"; shift 2 ;;
		--usegres) usegres="$2"; shift 2 ;;
		--gpuclock) clock="$2" ; shift 2 ;;
		--memclock) clock="$2" ; shift 2 ;;
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
	export gpus_per_node=16
	export NV_GPUCLOCK=1530
	export NV_MEMCLOCK=877
	echo "ERROR: DGX A100 is not supported yet.  Exiting"
	exit
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

RUNSCRIPT=submit_hpl_cuda${cudaver}.sh

# Set a name for the experiment
export EXPNAME=${nodes_per_job}node_${system}_$(date +%Y%m%d%H%M%S)
export EXPDIR=$(pwd)/results/${EXPNAME}

if [ -d $EXPDIR ]; then
	echo "ERROR: Directory already exists: $EXPDIR"
	exit 1
fi
mkdir -p $EXPDIR

# Grab nodelist and node count from the batch queue
export NODELIST=$(sinfo -p ${partition} | grep ${partition} | grep idle | awk '{print $6}')

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
for V in EXPDIR system nodes_per_job gpus_per_node gpuclock memclock  niters cudaver partition usehca maxnodes mpiopts gresstr total_nodes hpldat; do
	echo -n "${V}: "
        if [ x"${!V}" != x"" ]; then	
        	echo "${!V}"
	else
		echo "<Not Set>"
	fi
done
echo ""

jobid_list=()
for n in $(seq ${niters}); do
	P=1
	while [ $P -le ${total_nodes} ]; do
		HLIST=$(scontrol show hostlist $(tail +$P $MACHINEFILE | head -${nodes_per_job} | paste -d, -s))
		CMD="sbatch -N ${nodes_per_job} --time=${walltime}  -p ${partition} --parsable --ntasks-per-node=${gpus_per_node} ${gresstr} --export ALL,EXPDIR,NV_GPUCLOCK,NV_MEMCLOCK,HPLDAT,SYSTEM,GPUS_PER_NODE --exclusive -w ${HLIST} ${RUNSCRIPT}"
		echo $CMD
		jobid=$($CMD)
		if [ $? -ne 0 ]; then
			echo "ERROR: Unable to submit job.  Err=$?"
			# Cleanup experiment
			exit 1
		fi
		jobid_list+=($jobid)

		P=$(( $P + $nodes_per_job ))
	done
done

rm $MACHINEFILE

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
	squeue | grep -E $(echo ${jobid_list[@]} | tr ' ' '|') > $SQUEUEFN
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
echo "To rerun the verification: ./verify_hpl_experiment.py ${EXPDIR}"
echo ""


