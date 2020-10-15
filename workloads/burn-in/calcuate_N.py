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

for opt,arg in opts:
    if opt in ('--mem'):
        memsize=float(arg)
    elif opt in ('--nb'):
        nb=float(arg)
    elif opt in ('--ranks'):
        ranks=float(arg)
    elif opt in ('--help','h'):
        print_help()
        exit()
    else:
        print_help()
        exit()
    

print("MEM: ",memsize)
print("NB: ", nb)
print("RANKS: ", ranks)

# Find approximate value
v=math.sqrt(float(ranks)*float(memsize)*1024*1024/8)

print("")
print("Theoretical Max value of N: %d" % math.floor(v))

# modify value for best fit for NB and ranks
iv=math.floor(v/nb/ranks)

# Print list of N
print("")
print("List of N:")
for v in range(iv-4,iv+2):
    print("%d " % int(float(v)*nb*ranks),end="")

print("")
print("")

