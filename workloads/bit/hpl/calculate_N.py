#!/usr/bin/env python3

import sys
import getopt
import math

def print_help():
    print("")
    print("calculate_N.py -- A script to calculate a range of N values near maximum Memory Use")
    print("")
    print("Example:")
    print("    ./calculate.py --mem 32768 --nb 192 --ranks 8")
    print("")
    print("")
    print("Options:")
    print("    --mem : Total memory per GPU in MB")
    print("     --nb : value of NB")
    print("  --ranks : Total number of ranks (P*Q)")
    print("")
    print("")


opts,args=getopt.getopt(sys.argv[1:],'h',['mem=','nb=','ranks=','help'])

memsize=0
nb=0
ranks=0

for opt,arg in opts:
    if opt in ('--mem'):
        memsize=int(arg)
    elif opt in ('--nb'):
        nb=int(arg)
    elif opt in ('--ranks'):
        ranks=int(arg)
    elif opt in ('--help','h'):
        print_help()
        exit()
    else:
        print_help()
        exit()

if memsize == 0:
    print("ERROR: memsize not set")
    print_help()
    exit()

if nb == 0:
    print("ERROR: nb not set")
    print_help()
    exit()

if nb == 0:
    print("ERROR: ranks not set")
    print_help()
    exit()
    
print("")
print("HPL Parameter Calculator")
print("")
print("Total Memory Size (MB): %d" % memsize)
print("          Specified NB: %d" % nb)
print(" Total Number of Ranks: %d" % ranks)

# Find approximate value
v=math.sqrt(float(ranks)*float(memsize)*1024*1024/8)
max_val=round(math.floor(v/nb))*nb
ideal_val=int(math.floor(v/nb)*0.99)*nb

print("")
print("Theoretical Max value of N: %d" % max_val)
print("Ideal value of N (99%% of N): %d " % ideal_val)

# modify value for best fit for NB and ranks
# Make steps 0.5% in nb of max
istep=round((0.005*max_val)/nb)*nb

# Print list of N
print("")
print("List of N:")
for v in range(-3,3):
    n=ideal_val+v*istep
    print("%d " % n, end="")

print("")
print("")

