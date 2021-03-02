#!/bin/bash
#
# format_results.sh
#
# This script will take the results from an experiment and write
# them as a comma separated file to be read into a spreadsheet
# for additional analysis
#


if [ $# -ne 1 ]; then
	echo ""
	echo "./format_results.sh <experiment directory>"
	echo ""
	exit 1
fi

EXPDIR=$1

if [ ! -d ${EXPDIR} ]; then
	echo ""
	echo "Directory not found: ${EXPDIR}"
	echo ""
	exit 1
fi

grep -E 'HOSTLIST|WR0' ${EXPDIR}/*.out | \
	awk '{print $NF}' | 
	sed 'N;s/\n/ /' | sort \
	| awk 'BEGI{name=""}{name=$1; if (name!=oldname) {printf("\n%s,",name);oldname=name;}; printf("%s,",$2);}END{print("\n");}'
