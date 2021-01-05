#!/bin/bash

# ============================================================================ #
# Restrict GPUs in ssh sessions
# ============================================================================ #
deviceprop=$(systemctl show sshd.service -p DeviceAllow | grep -i nvidiactl)

if [ -z "$deviceprop" ] ; then
    systemctl set-property sshd.service DeviceAllow="/dev/nvidiactl"

    # on Ubuntu might be: DeviceAllow="char-pts" DeviceAllow="/dev/nvidiactl"
fi

# ============================================================================ #
# Patch /etc/slurm/epilog.d/40-lastuserjob-processes
# ============================================================================ #
genpatch_lastuserjob() {
cat << 'EOF' > /tmp/lastuserjob.patch
--- /etc/slurm/epilog.d/40-lastuserjob-processes
+++ 40-lastuserjob-processes.new
@@ -1,6 +1,10 @@
 #!/usr/bin/env bash
 set -ex
 
+if grep -q -w "$SLURM_JOB_USER" /etc/slurm/localusers.backup ; then
+    exit 0  # don't revoke access for these users
+fi
+
 if [ "$SLURM_JOB_USER" != root ]; then
     if killall -9 -u "$SLURM_JOB_USER" ; then
         logger -s -t slurm-epilog 'Killed residual user processes'

EOF
}

genpatch_lastuserjob

# check if already patched
patch -R -N --dry-run -u /etc/slurm/epilog.d/40-lastuserjob-processes -i /tmp/lastuserjob.patch

if [ $? -eq 1 ]; then
    patch -u /etc/slurm/epilog.d/40-lastuserjob-processes -i /tmp/lastuserjob.patch
fi

if [ -f "/tmp/lastuserjob.patch" ] ; then
    rm /tmp/lastuserjob.patch
fi

if [ -f "/etc/slurm/epilog.d/40-lastuserjob-processes.orig" ] ; then
    rm /etc/slurm/epilog.d/40-lastuserjob-processes.orig
fi

if [ -f "/etc/slurm/epilog.d/40-lastuserjob-processes.rej" ] ; then
    rm /etc/slurm/epilog.d/40-lastuserjob-processes.rej
fi

# ============================================================================ #
# Reload settings
# ============================================================================ #
systemctl daemon-reload
systemctl restart docker
scontrol reconfigure && \
  systemctl restart slurmd.service slurmctld.service slurmdbd.service


# ============================================================================ #
# Use file to indicate login patches
# ============================================================================ #
touch /etc/slurm/login_enable
