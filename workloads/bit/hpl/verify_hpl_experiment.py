#!/usr/bin/env python3
#
# verify_hpl_experiment.sh <DIRECTORY> (SYSTEM)
#
#  This script will do two things.
#    1) It will verify the performance against a reference, if the reference is available
#    2) It will verify performance based on jitter of all of the results.
#
# In the event there are failed jobs, the nodes and failure counts will be reported.

### TODO
#### Print total summary of experiment (total number of jobs, jobs per node, success, etc)
#### When a slow/bad job is found, write it out with the nodelist (compressed?)
#### 

import sys
import os
import glob
import re


### Define thresholds for slow jobs, in percent
HPLTHRESH=1.05
CPUTHRESH=1.05

def print_help():
        print("")
        print("verify_hpl_experiment.py <directory>")
        print("")
        print("\tThis script will validate the results for an HPL Burnin Experiment.  It validates")
        print("\thow each run completed as well as inspects the performance consistency of each run.")
        print("\tJobs that ran slow, did not pass internal validation, or did not complete, are reported")
        print("\tby nodes that were used.")
        print("")
        exit(1)

def format_hostlist(hostlist):
    s=""
    for h in sorted(hostlist):
        hs=h+":"+str(hostlist[h])
        if s=="":
            s=hs
        else:
            s=s+","+hs
  
    return s

def validate_case(label,d):
    val=""
    key=""
    for k in d:
        if val == "":
            val=d[k]
            key=k
        else:
            if val != d[k]:
                print("ERROR: Cases do not match: val=<{},{}> key=<{},{}>".format(val,d[k],key,k))
                print("ERROR: This should never happen.")
                return ""
    return val

def print_table(t_slow,t_total):
        for key in sorted(t_slow, key=t_slow.get,reverse=True):
                if t_slow[key] > 0:
                        print("{}: {} out of {}".format(key,t_slow[key],t_total[key]))
        print("")

print("")
print("Verifying HPL Burnin Results")
print("")

if len(sys.argv) <= 1: 
        print("Error: no command line arguments found.")
        print_help()

expdir=sys.argv[1]
if not os.path.exists(expdir):
        print('ERROR: {} does not exist'.format(expdir))
        print_help()

if not os.path.isdir(expdir):
        print('ERROR: {} is not a directory.'.format(expdir))
        print_help()

# Define hash tables to store results
cfg={}
n={}
nb={}
p={}
q={}
time={}
gflops={}
status={}
hl={}
tc={}
explist={}

fncnt=0
besttime=9999999.0
maxperf=0.0
minperf=1.0e+12

##HPL_AI   WR01L8R2      288000   288     4     2              23.55              6.763e+05        11.53998      2          4.539e+05

for fn in glob.glob(expdir + "/*.out", recursive=False):
        # Check 3 things, did the job complete, did the job pass or fail, what was the performance
        fncnt+=1

        file=open(fn,'r')

        tc[fn]=0
         
        for l in file.readlines():
                # Sometimes there may be a 2nd entry, only pull the last
                explist[fn]=1


                if re.search('WR',l):
                        # Check if this is regular HPL or HPL-AI
                        off=0
                        if (l.split()[0] == "HPL_AI"): off=1
                        cfg[fn]=l.split()[0+off]
                        n[fn]=int(l.split()[1+off])
                        nb[fn]=int(l.split()[2+off])
                        p[fn]=int(l.split()[3+off])
                        q[fn]=int(l.split()[4+off])
                        time[fn]=float(l.split()[5+off])
                        if time[fn] < besttime:
                                besttime=time[fn]
               
                        if (l.split()[0] == "HPL_AI"): 
                            gflops[fn]=float(l.split()[10])
                        else:
                            gflops[fn]=float(l.split()[6])
                        if gflops[fn] < minperf:
                                minperf=gflops[fn]
                        if gflops[fn] > maxperf:
                                maxperf=gflops[fn]

                #if re.search('^\|\|Ax-b\|\|\/eps',l):
                if re.search('\|\|Ax-b\|\|\_oo/\(eps',l):
                        if l.split()[3]=='PASSED':
                                status[fn]='passed'
                        elif l.split()[3]=='FAILED':
                                status[fn]='failed'
                        else:
                                status[fn]='unknown'    

                if re.search('^HOSTLIST:',l):
                        hl[fn]=l.split()[1]
                if re.search('End of Tests',l):
                        tc[fn]=1

        file.close()

# Vaidate each case and make sure they all have the same settings
if fncnt == 0:
    print("ERROR: No cases were found.  Either this is an invalid experiment directory or something we wrong.  Please check")
    print("")
    exit(1)

e_cfg=validate_case("run config",cfg)
if e_cfg == "": 
    print("ERROR: Of the {} files read, the run config tag was not found.  All results failed to run, please check each run manually.".format(fncnt))
    print("")
    exit(1)

e_n=validate_case("N",n)
e_nb=validate_case("NB",nb)
e_p=validate_case("P",p)
e_q=validate_case("Q",q)

# now analyze the data, record stats by node
# TODO, verify that all experiments have the same settings

slowcnt=0
failedcnt=0
unkcnt=0
dnccnt=0

t_slow={}
t_failed={}
t_unk={}
t_dnc={}
t_total={}

sum_slow=0
sum_failed=0
sum_unk=0
sum_dnc=0

for key in explist:
        isslow=0
        isfailed=0
        isunk=0
        isdnc=0
        for h in hl[key].split(','):
                if h not in t_total: t_total[h]=0
                t_total[h]+=1

                if h not in t_slow: t_slow[h]=0
                if h not in t_failed: t_failed[h]=0
                if h not in t_unk: t_unk[h]=0
                if h not in t_dnc: t_dnc[h]=0
                if tc[key] == 0:
                        t_dnc[h]+=1
                        dnccnt+=1
                        isdnc=1
                else:
                    if time[key] > besttime*HPLTHRESH:
                        t_slow[h]+=1
                        slowcnt+=1
                        isslow=1
                    if status[key] == 'failed':
                        t_failed[h]+=1
                        failedcnt+=1
                        isfailed=1
                    if status[key] == 'unknown':
                        t_unk[h]+=1
                        unkcnt+=1
                        isunk=1
        sum_slow+=isslow
        sum_failed+=isfailed
        sum_unk+=isunk
        sum_dnc+=isdnc

# Now sort and print results

print("")
print("Issues Found:")
print("")

stat=0
if slowcnt > 0:
        print("Slow Nodes:")
        print_table(t_slow,t_total)
        stat=1

if failedcnt > 0:
        print("Nodes on which Jobs Failed:")
        print_table(t_failed,t_total)
        stat=1

if unkcnt > 0:
        print("Nodes on which Jobs ended in Unknown State:")
        print_table(t_unk,t_total)
        stat=1 

if dnccnt > 0:
        print("Nodes on which Jobs did not complete:")
        print_table(t_dnc,t_total)
        stat=1

if stat == 0:
        print("No Issues Found")
        print("")

print("")
print("Summary:")
print("")
print("    Experiment Dir:",expdir)
print("        Total Jobs:", fncnt)
print("         Slow Jobs:", sum_slow)
print("       Failed Jobs:", sum_failed)
print("      Unknown Jobs:", sum_unk)
print("  Did Not Complete:", sum_dnc)
print("           HPL CFG:", e_cfg)
print("                 N:", e_n)
print("                NB:", e_nb)
print("               P*Q: {}*{}".format(e_p,e_q))
print("          Hostlist:", format_hostlist(t_total))
print("           MaxPerf:", maxperf,"GF")
print("           MinPerf:", minperf,"GF")
print("     Percent Range: {:.2f}%".format(100.0*(maxperf-minperf)/maxperf))
print("")

if stat!=0:
    print("Issues were found.  Refer to the README.md file for instructions on how to interpret the results.")

print("")

