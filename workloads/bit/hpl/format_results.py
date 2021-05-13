#!/usr/bin/python3
#
# format_results.py
#
# This script will format the results from an HPL
# experiment and write them into a comma separated file
# to be read into a spreadsheet for additional analysis.

import sys
import os
import subprocess
import getopt
import re

def print_help():
  
    print("")
    print("\tformat_results.py -d (experiment directory)\n")
    print("")
    sys.exit(1)

print("") 

try: 
    opts,args = getopt.getopt(sys.argv[1:],"d:",["d="])
except getopt.GetoptError:
    print_help()

dir = ""
for opt,arg in opts:
    if opt == '-h':
        print_help()
    elif opt in ("-d","--dir"):
        expdir=arg

if expdir == "":
    print("ERROR: Directory must be specified.")
    print_help()

if not os.path.isdir(expdir): 
    print("ERROR: Specified path is not a directory.  DIR="+dir)
    print("ERROR: exiting")
    print("")
    sys.exit(1)

# Create a results dictionary
res={}

# Now loop over all .out files found in dir
for fn in os.listdir(expdir):
    if not fn.endswith(".out"):
        continue

    # For each file, find the HOSTLIST and performance metric
    with open(expdir+"/"+fn,"r") as fp:
        hosts=""
        perf=""
        for line in fp:
            l=line.strip()
            # Matching: HOSTLIST node-001,node-002
            if(re.match('HOSTLIST',l)):
                if hosts != "":
                    print("ERROR: Found HOSTLIST twice in "+fn)
                hosts=l.split()[-1]

           ## Matching:  WR01C2C8      180224   144     4     4              50.27              7.763e+04
            m=re.match('^W\w\d{2}\w\d\w\d (.*)$',l)
            if m:
                # Silently grab the last one
                perf=l.split()[-1]

        # Compress nodelist

        cmd=['scontrol','show','hostlist',hosts]
        cout=subprocess.run(cmd,stdout=subprocess.PIPE)
        chosts=cout.stdout.decode('utf-8').strip()

        if chosts in res:
            res[chosts].append(perf)
        else:
            res[chosts]=[perf]

## Now all the data have been read, lets print it out
print("")
print("Comma Separated Results for Experiment: "+expdir)
print("")

## Print headers
maxexp=0
for k,v in sorted(res.items()):
    l=len(res[k])
    if l > maxexp:
        maxexp=l

print("Nodelist;",end="")
for n in range(1,maxexp+1):
    print("Exp %d;" % n,end="")
print("")

for k,v in sorted(res.items()):
    print("%s;%s" % (k,";".join(res[k])))

        


   
