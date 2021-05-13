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

export HPL_DIR=${HPL_DIR:-$(cd $(dirname $0) && pwd)} # The shared directory where scripts, data, and results are stored
export HPL_SCRIPTS_DIR=${HPL_SCRIPTS_DIR:-${HPL_DIR}} # The shared directory where these scripts are stored

## Set default options
niters=5
partition="batch"
usegres=1
hplai=0
maxnodes=9999
grestype=""
mpiopts=""
walltime=1:00:00
verbose=0
nores=0
cruntime=singularity
container="nvcr.io/nvidia/hpc-benchmarks:21.4-hpl"
ORDER_CMD="cat"
slurmopts=""

print_usage() {
   cat << EOF

${0} [options]

Launch an HPL Burnin test.

Required Options:
    -s|--sys <SYSCFG>
        * Set to the system type on which to run.  Ex: dgx1v, dgx2, dgxa100, or a path to a script file with custom system settings
    -c|--count <Count>
        * Set to the number of nodes to use per job

Other Options:
    -i|--iters <Iterations>
        * Set to the number of iterations per experiment.  Default is ${niters}."
    -p|--part <Slurm Partition>
        * Set the Slurm partition to use.  Default is ${partition}."
    -a|-A|--account <Slurm Account>
        * Set the Slurm accoutn to use.  Default is None."
    -m|--maxnodes <Number_of_nodes>
        * Set the maximum number of nodes to use per experiment.  This is used for testing.  Default is all of them."
    --mpiopts <Options>
        * Sets string with additional OpenMPI options to pass to mpirun.  Default is none.
    --usegres <Val>
	* Enable/disable use of GRES options in Slurm (1/0).  Default is ${usegres}.
    --grestype <val>
        * Specify if you need to specify a specific gputype when submitting to your batch system with gpu options.  
    --container <container URL>
        * Set container to use
    --cruntime <container runtime>
	* Specify container runtime.  Options are singularity, enroot, and bare (bare-metal)
    --hplai 
        * Run HPL-AI benchmark
    --nores
	* Do not request specific nodes or try to control how jobs are placed on the system (better for experiments while in production)
    -w 
        * Node include list (must overlap with nodes in the partition)
    -x 
        * Node exclude list
    --slurmopts
        * Use to set any slurm variables not supported by other options.  Ex: --slurmopt "--exclusive --constraint su2"
    -r|--random
        * Randomize which nodes get used each iteration
    -v|--verbose
        * Provide extra logging information
    --hpldat <FILE>
        * Use a specific HPL.dat file for the experiment.  The P and Q values in the file will be used and override the -c option.

EOF

exit
}

function find_hpl_dat_file() {

    local system=$1
    local gpus_per_node=$2
    local nnodes=$3
    locxal hplai=$4

    HPLDATFN=${HPL_FILE_DIR}/HPL.dat_${nnodes}N_${system}
    if [ x"$hplai" == x"1" ]; then
        HPLDATFN=${HPLDATFN}_ai
    fi
    echo $HPLDATFN

}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) print_usage ; exit 0 ;;
        -s|--sys) system="$2"; shift 2 ;;
        -c|--count) nodes_per_job="$2"; shift 2 ;;
        -i|--iters) niters="$2"; shift 2 ;;
        -p|--part) partition="$2"; shift 2 ;;
        -a|-A|--account) account="-A $2"; shift 2 ;;
        -t|--walltime) walltime="$2"; shift 2 ;;
        -r|--random) ORDER_CMD=shuf; shift 1;;
        -v|--verbose) verbose=1; shift 1 ;;
        -w) includelist="$2"; shift 2 ;;
        -x) excludelist="$2"; shift 2 ;;

        --hplai) hplai=1; shift 1 ;;
        --nores) nores=1; shift 1 ;;
        -m|--maxnodes) maxnodes="$2"; shift 2 ;;	
        --mpiopts) mpiopts="$2"; shift 2 ;;
        --usegres) usegres="$2"; shift 2 ;;
        --grestype) grestype="$2"; shift 2 ;;
        --hpldat) hpldat="$2"; shift 2 ;;
        --cruntime) cruntime="$2"; shift 2 ;;
        --container) container="$2"; shift 2 ;;
        --slurmopts) slurmopts="$2"; shift 2 ;;
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
    export SYSCFG=syscfg-dgx1v.sh
    export GPUMEM=16
elif [ x"${system}" == x"dgx1v_32G" ]; then
    export gpus_per_node=8
    export SYSCFG=syscfg-dgx1v.sh
    export GPUMEM=32
elif [ x"${system}" == x"dgx2" ]; then
    export gpus_per_node=16
    export SYSCFG=syscfg-dgx2.sh
elif [ x"${system}" == x"dgxa100_40G" ]; then
    export gpus_per_node=8
    export SYSCFG=syscfg-dgxa100-40gb.sh
    export GPUMEM=40
elif [ x"${system}" == x"dgxa100_80G" ]; then
    export gpus_per_node=8
    export SYSCFG=syscfg-dgxa100-80gb.sh
    export GPUMEM=80
else
    echo "GENERIC SYSTEMS are not supported yet"
    if [ ! -f ${system} ]; then
        echo "ERROR: For a generic system, a syscfg file must be specified (${system})"
        exit 1
    fi

    export SYSCFG=${system}
    export gpus_per_node=$(cat ${system} | GPU_AFFINITY | cut -f2 -d= | awk -F: '{print NF}' )
    echo "HERE: $SYSCFG gpus=$gpus_per_node"
fi

case ${SYSCFG} in
    *.sh)
    if [ ! -f ${SYSCFG} ]; then
        echo "ERROR: SYSCFG file ${SYSCFG} not found.  Exiting."
        exit 1
    fi
    ;;
esac
	   
if [ x"${usegres}" == x"1" ]; then
    if [ x"${grestype}" != x"" ]; then
        gresstr="${grestype}:"
    else
        gresstr=""
    fi
    gresstr="--gpus-per-node=${gresstr}${gpus_per_node}"
fi

# Setup the HPLAI export variable
export HPLAI=${hplai}

if [ x"${cruntime}" != x"" ]; then
    # Validate runtime is correct
    case "${cruntime}" in
        singularity)
            echo "INFO: Using singularity runtime"
            # Pull container if needed and convert to singluarity
            if [ x"$(which singularity)" == x"" ]; then
                echo "ERROR: Singlularity not found, check your path"
                exit 1
            fi
            if [ ! -f ${container} ]; then
                # Since the file doesn't exist, assume the CONTAINER is a URI
                export CONT=docker://${container} 
            else
                export CONT=${PWD}/${container}
            fi
        ;;
        enroot)
            echo "INFO: Using enroot runtime"
            # Need to convert the container and change all the slashes except the last one to #
            # This expression below is probably not robust.
            if [ ! -f ${container} ]; then
                # Since the file doesn't exist, assume the CONTAINER is a URI
                export CONT=$(echo ${container} | sed 's/\//#/')
            else
                export CONT=${PWD}/${container}
            fi
        ;;
        bare)
            echo "INFO: Using bare-metal runtime"
            echo "ERROR: Baremetal not supported yet"
            export CONT=""
            exit 2 ;;
        *) echo "ERROR: Runtime ${cruntime} is not supported, exiting"
            exit 1 ;;
        esac
else
    echo "ERROR: Container runtime (--cruntime) must be set"
    exit 1
fi

export CRUNTIME=${cruntime}

### Find the right HPL.dat file
if [ x"${hpldat}" == x"" ]; then
    HPLDATFN=${HPL_DIR}/hplfiles/$(find_hpl_dat_file ${system} ${gpus_per_node} ${nodes_per_job} ${hplai})
else
    echo ""
    echo "An HPL.dat file has been manually specified."
    if [ ! -f ${hpldat} ]; then
        echo "ERROR: HPL.dat file specified, but not found.  ${hpldat}"
        exit 1
    fi
	# Line 10 is Number of PQ pairs, line 11 is P, line 12 is Q
    NPQ=$(cat ${hpldat} | tail -n +10 | head -1 | awk '{print $1}')
    P=$(cat ${hpldat} | tail -n +11 | head -1 | awk '{print $1}')
    Q=$(cat ${hpldat} | tail -n +12 | head -1 | awk '{print $1}')
    if [ ${NPQ} -ne 1 ]; then
	echo "WARNING: Node allocation is only going to match the first P*Q pair"
    fi

    nodes_per_job=$(( P * Q / gpus_per_node ))
    echo "Overriding nodes_per_job, using nodes_per_job=${nodes_per_job} to match settings in ${hpldat}"
    echo ""
    export HPLDATFN=${hpldat}
fi

export SYSTEM=${system}
export GPUS_PER_NODE=${gpus_per_node}

# Set a name for the experiment
export EXPNAME=${nodes_per_job}node_${system}_$(date +%Y%m%d%H%M%S)
if [ x"${hplai}" == x"1" ]; then
    export EXPNAME=${EXPNAME}_ai
fi
export EXPDIR=$(pwd)/results/${EXPNAME}

if [ -d $EXPDIR ]; then
    echo "ERROR: Directory already exists: $EXPDIR"
    exit 1
fi
mkdir -p $EXPDIR

# Grab nodelist and node count from the batch queue

# look for all idle nodes in the partition and creating a working nodelist as $MACHINEFILE
export NODELIST=$(sinfo -p ${partition} | grep ${partition} | grep " idle " | awk '{print $6}')
export MACHINEFILE=/tmp/mfile.$$
scontrol show hostname ${NODELIST} > $MACHINEFILE

# If there is an include list, process that
if [ x"${includelist}" != x"" ]; then
    echo "Include List: ${includelist}"
    export INCLUDELIST=/tmp/mfile.include.$$
    scontrol show hostname ${includelist} > $INCLUDELIST
    cat ${MACHINEFILE} ${INCLUDELIST} | sort | uniq -c | awk '{if ($1>1) print $2}' > ${MACHINEFILE}.t2
    mv ${MACHINEFILE}.t2 ${MACHINEFILE}
    rm ${INCLUDELIST}
fi

# If there is an exclude list, process that
if [ x"${excludelist}" != x"" ]; then
    echo "Exclude List: ${excludelist}"
    export EXCLUDELIST=/tmp/mfile.exclude.$$
    scontrol show hostname ${excludelist} > $EXCLUDELIST
    cat ${MACHINEFILE} ${MACHINEFILE} ${EXCLUDELIST} | sort | uniq -c | awk '{if ($1==2) print $2}' > ${MACHINEFILE}.t2
    mv ${MACHINFILE}.t2 ${MACHINEFILE}
    rm ${EXCLUDELIST}
fi

# Trim the nodelist down to the maxnode setting
cat ${MACHINEFILE} | head -${maxnodes} > ${MACHINEFILE}.t2
mv ${MACHINEFILE}.t2 ${MACHINEFILE}

export total_nodes=$(cat $MACHINEFILE | wc -l)

if [ $total_nodes -eq 0 ]; then
    echo "ERROR: Unable to find any idle nodes in partition=${partition}.  Exiting."
    echo ""
    exit 1
fi

if [ $total_nodes -lt $nodes_per_job ]; then
    echo "ERROR: Not enough nodes idle ($total_nodes) for a single job ($nodes_per_job).  Exiting."
    echo ""
    exit 1
fi

echo  ""
echo "Working Nodelist: $(scontrol show hostlist $(cat $MACHINEFILE | tr '\n' ','))"
echo ""

### Report all variables
echo ""
echo "Experiment Variables:"
for V in HPL_DIR HPL_SCRIPTS_DIR EXPDIR system cruntime CONT nodes_per_job gpus_per_node niters partition slurmopts maxnodes mpiopts gresstr total_nodes hpldat hplai; do
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
    P=1
    INST=1

    if [ ${nores} != 1 ]; then
        echo "Working Nodelist: $(scontrol show hostlist $(cat $MACHINEFILE | tr '\n' ','))"
        cat ${MACHINEFILE} | ${ORDER_CMD} > $HFILE
    fi

    while [ $(( P + nodes_per_job - 1 ))  -le ${total_nodes} ]; do
        # Create hostlist per iter
        if [ ${nores} == 1 ]; then
            HLIST=""
            DEPENDENCY="--dependency=singleton"

            if [ x"${includelist}" != x"" ]; then
                echo "Include lists are not supported with --nores"
                ### You cannot provide an include list, you can only include the full list to use, not a range. 
                ### So the includelist is not supported in this mode
                ###  DEPENDENCY="$DEPENDENCY -w ${includelist}" 
            fi

            if [ x"${excludelist}" != x"" ]; then
                DEPENDENCY="$DEPENDENCY -x ${excludelist}" 
            fi
        else
            HLIST="-w $(scontrol show hostlist $(tail -n +$P ${HFILE} | head -${nodes_per_job} | sort | paste -d, -s))"
            DEPENDENCY=""
        fi

        # create a workdir for each job
        WORKDIR=${EXPDIR}/tmp/tmp.$$.$(date +%s)
        mkdir -p ${WORKDIR}
        if [ $? -ne 0 ]; then
            echo "ERROR: Unable to create working directory $WORKDIR.  Exiting"
            exit 1
        fi

        # Copy working files to unique directory
        cp ${HPLDATFN} ${WORKDIR}/HPL.dat
        if [ -f ${SYSCFG} ]; then
            cp ${SYSCFG} ${WORKDIR}/syscfg.sh
            export SYSCFGVAR=syscfg.sh
        else
            export SYSCFGVAR=${SYSCFG}
        fi

        # Submit the job in the workdir
        pushd ${WORKDIR} > /dev/null 2>&1

        CMD="sbatch -J sa-bit:burnin-case-${INST} -N ${nodes_per_job} "
        CMD+="--time=${walltime} ${account} -p ${partition} ${slurmopts} "
        CMD+="--ntasks-per-node=${gpus_per_node} ${gresstr} --parsable --exclusive "
        CMD+="-o ${EXPDIR}/${EXPNAME}-%j.out ${HLIST} ${DEPENDENCY} "
        CMD+="--export ALL,CONT,SYSCFG,SYSCFGVAR,GPUMEM,CRUNTIME,HPLAI,EXPDIR "
        CMD+="${HPL_DIR}/submit_hpl.sh"
                 
        if [ ${verbose} -eq 1 ]; then
            echo "Submitting:  $CMD"
        fi
            jobid=$($CMD) 
            if [ $? -ne 0 ]; then
                echo "ERROR: Unable to submit job.  Err=$?"
                # Cleanup experiment
                #exit $? 
            fi

            popd > /dev/null 2>&1

            jobid_list+=($jobid)

            P=$(( $P + $nodes_per_job ))
            INST=$(( $INST + 1 ))
     done
    if [ $(( P - 1 )) -lt ${total_nodes} ]; then
        # Print out the extra nodes not used
        HLIST=$(scontrol show hostlist $(tail -n +$P ${HFILE} | sort | paste -d, -s))
        echo ""
        echo "Unused nodes for this iteration: ${HLIST}"
    fi
    echo ""
done

wait

rm -f ${HFILE}
rm -f ${MACHINEFILE}

# Now watch and wait on the experimet
# Group jobs into running, waiting

total_jobs=${#jobid_list[@]}
SQUEUEFN=/tmp/squeue.data.$$

jobs_tbd=1
p=0
display_row=25

echo ""
echo "Experiment Directory: ${EXPDIR}"
echo ""

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
echo "Nodes Per Job: ${nodes_per_job}"
echo "Verify Log: ${VLOGFN}"

echo ""
echo "To rerun the verification: ${HPL_SCRIPTS_DIR}/verify_hpl_experiment.py ${EXPDIR}"
echo ""


