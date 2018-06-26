#!/usr/bin/env bash

# example: DGX 1-36 are IPs .1 - .36
for i in $(seq -w 01 36) ; do
    ipmi_ip=10.0.1.${i}
    ipmi_cmd="ipmitool -I lanplus -U dgxuser -P dgxuser -H ${ipmi_ip}"

    echo -n "${ipmi_ip}: "

    # get mac of first lan interface
    #${ipmi_cmd} raw 0x30 0x19 0x00 0x02 | tail -c 18 | tr ' ' ':'

    ### Re-provision/install nodes
    ## disable 60s boot order timeout
    ${ipmi_cmd} raw 0x00 0x08 0x03 0x08
    ## set to boot pxe/efi on next boot only
    ${ipmi_cmd} chassis bootdev pxe options=efiboot
    ## power cycle
    ${ipmi_cmd} power cycle

done
