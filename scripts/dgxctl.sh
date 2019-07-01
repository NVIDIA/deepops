#!/usr/bin/env bash

# Set configuration
. config/pxe/ipmi.conf


OPTIND=1
IPMI_HOST_LIST="config/pxe/ipmi_host_list"
install=0
progress=0
upgrade=0
config_host=
host_list=0
install_log=0
ssh_check=0
show_bmc=0
validate=0
ipmi=
retry=0
fw_target=all

usage () {
    echo "Manage DGX install/upgrade/configure/check process"
    echo
    echo "Usage: $0 [arguments]"
    echo
    echo "General Arguments:"
    echo "  -h        Show help"
    echo "  -x        Show list of DGX host IP addresses from DHCP server"
    echo "  -y        Show DGX server install log from provisioning container"
    echo "  -z        Verify DGX are available via SSH connection"
    echo "  -b        Show DGX BMC IP matched with host IP (use with -z)"
    echo "  -w <opt>  Control DGX power status via IPMI (options: on, off)"
    echo
    echo "Install Arguments:"
    echo "  -i        Run install process"
    echo "  -p        Show install progress"
    echo "  -f <file> Use alternate IP file (default: ${IPMI_HOST_LIST})"
    echo
    echo "Update/Configuration arguments:"
    echo "  -u        Run upgrade and configure process on all hosts"
    echo "  -l <host> Run upgrade and configure process on single host"
    echo "  -q        Re-run only failed upgrade/configuration tasks"
    echo "  -r        Update FRU (default: only update SBIOS and BMC)"
    echo
    echo "Validation/check arguments:"
    echo "  -v        Run the validation checks on all hosts"
    echo "  -l <host> Run the validation checks on a single host"
    exit 0
}

while getopts "h?pif:ul:rxyzbvw:q" opt; do
    case "$opt" in
        h|\?)
            usage
            ;;
        i) install=1
            ;;
        p) progress=1
            ;;
        f) IPMI_HOST_LIST="${OPTARG}"
            ;;
        u) upgrade=1
            ;;
        l) config_host="${OPTARG}"
            ;;
        r) fw_target="FRU"
            ;;
        x) host_list=1
            ;;
        y) install_log=1
            ;;
        z) ssh_check=1
            ;;
        b) show_bmc=1
            ;;
        v) validate=1
            ;;
        w) ipmi="${OPTARG}"
            ;;
        q) retry=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))
[ "$1" == "--" ] && shift

test -f "${IPMI_HOST_LIST}"
if [ $? -ne 0 ] ; then
    echo File not found: "${IPMI_HOST_LIST}"
    exit 1
fi

if [ "${progress}" -eq 1 ] ; then
    # Chassis identify information:
    #    $ sudo ipmitool -I lanplus -H <IP> -U dgxuser -P dgxuser chassis identify force
    #    Chassis identify interval: indefinite
    #    $ sudo ipmitool -I lanplus -H <IP> -U dgxuser -P dgxuser raw 0x00 0x01
    #     41 10 60 10
    #     $ sudo ipmitool -I lanplus -H <IP> -U dgxuser -P dgxuser chassis identify 0
    #     Chassis identify interval: off
    #     $ sudo ipmitool -I lanplus -H <IP> -U dgxuser -P dgxuser raw 0x00 0x01
    #      41 10 40 10
    echo "Install progress (host list: ${IPMI_HOST_LIST})":
    echo 
    while read -u10 IPMI_HOST_IP ; do
        echo -n "${IPMI_HOST_IP}: "
        chassis_ident_state=$(sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} raw 0x00 0x01 | awk '{print $3}')
        if [ "${chassis_ident_state}" == "60" ] ; then
            echo installing...
        elif [ "${chassis_ident_state}" == "40" ] ; then
            echo finished
        else
            echo status unknown...
        fi
    done 10<${IPMI_HOST_LIST}
elif [ "${install}" -eq 1 ] ; then
    echo Initiating PXE install process via BMC host list: ${IPMI_HOST_LIST}
    while read -u10 IPMI_HOST_IP ; do
        echo -n "${IPMI_HOST_IP}: "

        # make sure BMC is reachable
        sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} bmc info >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Error communicating with BMC"
            continue
        fi
        echo -n "available | "

        # disable IPMI boot device selection 60s timeout
        sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} raw 0x00 0x08 0x03 0x08 >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo -n "config ERROR"
            continue
        fi
        echo -n "config(1) | "

        # set baseline (boot to disk, efi, persistent)
        sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} raw 0x00 0x08 0x05 0xe0 0x08 0x00 0x00 0x00 >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo -n "config ERROR"
            continue
        fi
        echo -n "config(2) | "

        # set boot device to PXE, EFI, next boot only. Needed when defaulting to install vs boot local disk
        sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} chassis bootdev pxe options=efiboot >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo -n "pxe ERROR"
            continue
        fi
        echo -n "pxe | "

        # check that we have the correct bitmask - a004000000
        BOOT_CODE=a004000000
        boot_param=$(sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} chassis bootparam get 0x05 | egrep "^Boot parameter data:" | awk '{print $4}')
        if [ "${boot_param}" != "${BOOT_CODE}" ] ; then
            echo "Error: boot parameter incorrect (${boot_param})"
            continue
        fi

        # power off/on host
        sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} power off >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "power off ERROR"
            continue
        fi
        sleep 5
        sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} power on >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "power on ERROR"
            continue
        fi
        echo "reset | installing..."

        # turn on chassis identifier light to indicate installation is in progress
        sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} chassis identify force >/dev/null 2>&1

    done 10<${IPMI_HOST_LIST}
    echo The install process will take approximately 15 minutes
elif [ "${upgrade}" -eq 1 ] || [ "${validate}" -eq 1 ] ; then
    # Get host list and generate ansible inventory file
    host_list=$(curl -s localhost/hosts | grep 54:ab:3a | awk '{print $2}')

    inventory_file=$(mktemp)
    echo "[all:vars]" > "${inventory_file}"
    echo "ansible_user=${DGX_USERNAME}" >> "${inventory_file}"
    echo "ansible_ssh_pass=${DGX_PASSWORD}" >> "${inventory_file}"
    echo "ansible_sudo_pass=${DGX_PASSWORD}" >> "${inventory_file}"
    echo "[hosts]" >> "${inventory_file}" >> "${inventory_file}"

    for host in ${host_list} ; do
        echo "${host}" >> "${inventory_file}"
        # remove stale host key in case we did a re-install
        ssh-keygen -f "~/.ssh/known_hosts" -R "${host}" >/dev/null 2>&1
    done

    # Run configuration scripts
    if [ "${upgrade}" -eq 1 ] ; then
        echo "The upgrade process will take upwards of 30 minutes"
        echo "Start time: $(date)"

        if [ "${retry}" -eq 1 ] ; then
            ansible-playbook -i "${inventory_file}" -l "@${ANSIBLE_REPO}/playbook.retry" "${ANSIBLE_REPO}/playbook.yml"
        elif [ "x${config_host}" != "x" ] ; then
            ansible-playbook -i "${inventory_file}" -l "${config_host}" "${ANSIBLE_REPO}/playbook.yml" --extra-vars \"target_fw=${fw_target}\"
        else
            ansible-playbook -i "${inventory_file}" -l hosts "${ANSIBLE_REPO}/playbook.yml" --extra-vars \"target_fw=${fw_target}\"
        fi
    elif [ "${validate}" -eq 1 ] ; then
        echo "The validation process will take approximately 10 minutes"
        echo "Start time: $(date)"

        if [ "x${config_host}" != "x" ] ; then
            echo ansible-playbook -i "${inventory_file}" -l "${config_host}" "${ANSIBLE_REPO}/playbook.yml"
        else
            echo ansible-playbook -i "${inventory_file}" -l hosts "${ANSIBLE_REPO}/playbook.yml"
        fi
    fi

    rm -f "${inventory_file}"
    echo "End time: $(date)"
elif [ "${host_list}" -eq 1 ] ; then
    curl localhost/hosts
elif [ "${install_log}" -eq 1 ] ; then
    curl localhost/log
elif [ "${ssh_check}" -eq 1 ] ; then
    # Get host list
    host_list=$(curl -s localhost/hosts | grep 54:ab:3a | awk '{print $2}')
    # Check hosts
    for host in ${host_list} ; do
        echo -n "${host}: "
        ping -c1 "${host}" >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "unavailable"
            continue
        fi
        # remove stale host key in case we did a re-install
        ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${host}" >/dev/null 2>&1
        if [ "${show_bmc}" -eq 1 ] ; then
            sshpass -p "${DGX_PASSWORD}" ssh -oStrictHostKeyChecking=no dgxuser@"${host}" "echo ${DGX_PASSWORD} | sudo -S ipmitool lan print 1 2>/dev/null | egrep '^IP Address' | tail -1 | awk '{print \$4}'" 2>&1 | grep -v Warning
        else
            sshpass -p "${DGX_PASSWORD}" ssh -oStrictHostKeyChecking=no dgxuser@"${host}" uptime 2>&1 | grep -v Warning
        fi
    done
elif [ "x${ipmi}" != "x" ] ; then
    # Power on/off DGX via IPMI
    if [ "x${config_host}" != "x" ] ; then
        echo -n "${config_host}: "
        if [ "${ipmi}" == "on" ] ; then
            sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H "${config_host}" power on
        elif [ "${ipmi}" == "off" ] ; then
            sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H "${config_host}" power off
        fi
    else
        while read -u10 IPMI_HOST_IP ; do
            echo -n "${IPMI_HOST_IP}: "
            if [ "${ipmi}" == "on" ] ; then
                sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} power on
            elif [ "${ipmi}" == "off" ] ; then
                sudo ipmitool -I lanplus -U ${IPMI_USERNAME} -P ${IPMI_PASSWORD} -H ${IPMI_HOST_IP} power off
            fi
        done 10<${IPMI_HOST_LIST}
    fi
else
    usage
fi
