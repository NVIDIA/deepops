
DGXie: PXE Boot DGX Install Environment
===

This repo is intended to be used to automate provisioning of DGX-1 Servers over the network. The tools will automatically configure, reboot, re-install and re-configure the DGX with minimal commands.

You will need a computer (i.e. a laptop) running Ubuntu 16.04 which has two network connections, i.e built-in and USB/Ethernet adapter.

If you are setting up a laptop from scratch, see the "Setting up a new laptop" section at the end of the README

Otherwise, follow each of the sections below in order:

## Connect the laptop to the network

Connect the built-in ethernet to the private network where the DGX are connected, and the usb-ethernet dongle to a public, internet accessible network, if available.
 The install process does not require an internet connection, but it may be usefull later for updating or installing extra software.

This assumes the built-in ethernet interface is the "public" network and the usb-ethernet dongle is the "private" network where the DGX are connected

In addition to the network connection to the DGX data network, the laptop will need to have access to the management network where the DGX BMCs are connected.
 This can be shared through the private interface connected to the DGX data network or through the second interface connected to the public network.

In some cases you may need to:
* Disconnect the network uplink from DGX data networks
* Set the DHCP helper IP in the ToR switches to point to the private interface on the laptop where DGXie runs its servers

The private interface on the laptop should have a static IP/netmask/etc. (i.e 192.168.1.1/24)

To configure the private interface on the laptop, you can either use the Network Manager GUI in Ubuntu Desktop, or configure
 via `nmcli` in a terminal:

List network devices:

```console
nmcli con show
```

Modify settings of private interface:

```console
sudo nmcli c modify "Belkin USB-ethernet adapter" ipv4.addresses 192.168.1.1/24 ipv4.dns 8.8.8.8 ipv4.gateway 192.168.1.1
```

Show device properties:

```console
nmcli con show "Belkin USB-ethernet adapter"
```

Activate interface:

```console
sudo nmcli con up "Belkin USB-ethernet adapter"
```

### BMC considerations

You will need a list of BMC IP addresses for each DGX Server to be provisioned.

The laptop will likely need a second network connection to the BMC network, this can be accomplished by adding a second IP address to the network interface
 used to connect to the DGX network, or by connecting a second network interface, such as the USB-ethernet adapter, to the network and assigning an IP in
 the BMC subnet.
 
If the DHCP server for the BMC network is disconnected, a logical choice for IP address would be the gateway IP for the BMC subnet. You can get this IP
 from Penguin or from a DGX BMC via IPMI.

## Run the Dgxie service container

If you need to modify the default network settings, modify `docker-compose.yml` to edit the environment variables to configure DGXie.
 See the section at the end of the README for all configuration options. You may need to configure the DGXie container with
 public and private interface names, and IP information to configure the DHCP server if you are not using 192.168.1.0/24.

Run containers:

```console
sudo docker-compose build
sudo docker-compose up -d
```

Make sure the containers are running with: `sudo docker ps -a`

You can check the container logs with (you may have to substitute a different container name): `sudo docker logs deepops_dgxie_1`

## Provision DGX

The DGX install process will take approximately **15** minutes.

**Steps:**
* Modify the *ipmi_host_list* script to contain the BMC IP address of each DGX which needs to be re-imaged, one per line
* Modify the *configuration* file to contain the username and password of the DGX BMCs. This file also contains the default username and password of the DGX ISO,
 which should not need to be changed.
* Run *dgxctl.sh* with the `-i` flag to start the install process (see example below)

The *dgxctl.sh* script will iterate over each BMC IP address, one at a time, making sure it's up, disabling the boot order timeout, setting the system to PXE boot
 and power-cycling the system via BMC.

The DGX will immediately power-cycle and attempt to boot from the connected network interface. The DGXie container provides the DHCP and PXE server which the DGX
 will use to automatically run the install process without user intervention. When the install process is finished, the DGX will automatically reboot and boot to
 the first hard disk, which now contains the DGX Server OS.

The *dgxctl.sh* script will turn on the DGX chassis identification light during the install. If there is a DGX with a suspected install problem, you can either
 check the DGX via virtual console on the BMC IP address or connect a physical console to the affected DGX, identified by a lit chassis identification light.

The default BMC credentials are:

```console
Username: dgxuser
Password: dgxuser
```

The default DGX OS user login credentials are:

```console
Username: dgxuser
Password: DgxUser123
```

Here's an example of running *dgxctl.sh* and the expected output:

```console
$ ./dgxctl.sh -i
Initiating PXE install process via BMC host list: ipmi_host_list

10.0.1.1: available | config(1) | config(2) | pxe | reset | installing...
10.0.1.2: available | config(1) | config(2) | pxe | reset | installing...
```

If a system fails, you'll see an error:

```console
$ ./dgxctl.sh -i
Initiating PXE install process via BMC host list: ipmi_host_list

10.0.1.1: Error communicating with BMC on host: 10.0.1.1
```

You can check the install progress with the `-p` flag:

```console
$ ./dgxctl.sh -p
Install progress (host list: ipmi_host_list):

10.0.1.1: installing...
10.0.1.2: installing...

$ ./dgxctl.sh -p
Install progress (host list: ipmi_host_list):
 
10.0.1.1: finished
10.0.1.2: finished
```

If you want to specify a different BMC IP file, use the `-f <filename>` flag. You can see the help options with the `-h` flag.

### Provisioning API

DGXie provides several methods to obtain data, these should be run from the laptop outside of the DGXie container

Get list of hosts:

```console
$ ./dgxctl.sh -x
+------------------------------------------------------------------------------
| DHCPD ACTIVE LEASES REPORT
+-----------------+-------------------+----------------------+-----------------
| IP Address      | MAC Address       | Expires (days,H:M:S) | Client Hostname
+-----------------+-------------------+----------------------+-----------------
| 192.168.1.3     | 54:ab:3a:d6:61:9d |             11:43:56 |
| 192.168.1.4     | 54:ab:3a:da:c4:8b |             11:43:53 |
+-----------------+-------------------+----------------------+-----------------
| Total Active Leases: 2
| Report generated (UTC): 2017-11-09 15:16:51
+------------------------------------------------------------------------------
```

Get list of finished installs:

```console
$ ./dgxctl.sh -y
== LOG OPENED ==
2017-11-09 15:02:23.464795: start - 192.168.1.4
2017-11-09 15:02:23.798555: start - 192.168.1.3
2017-11-09 15:08:43.272009: end - 192.168.1.4
2017-11-09 15:08:52.148569: end - 192.168.1.3
```

### Monitoring the DGX install and confirming it has completed

Once the output of `./dgxctl.sh -y` and `./dgxctl.sh -p` show that the install has ended/finished, it will take a few additional minutes for the DGX
 to reboot and boot into the new operating system on the disk.
 
You can run the command below to check whether the DGX are ready and available to move on to the next steps:

```console
$ ./dgxctl.sh -z
192.168.1.3:  07:29:51 up 10:44,  0 users,  load average: 0.16, 0.16, 0.11
192.168.1.4:  07:29:51 up 10:45,  0 users,  load average: 0.19, 0.14, 0.15
```

## End

## Misc Tasks

**Power on/off all DGX via IPMI**

```console
$ ./dgxctl.sh -w on
10.0.1.1: Chassis Power Control: Up/On
10.0.1.2: Chassis Power Control: Up/On
```

**Power on/off a single DGX via IPMI**

```console
$ ./dgxctl.sh -w off -l 10.0.1.1
10.0.1.1: Chassis Power Control: Down/Off
```

# Optional information

This information is not required if you are using a pre-configured laptop. It's left here for reference if you are starting from scratch.

## Setting up a new laptop

### Setting up a system to run the DGXie tools:

You will need a laptop running Ubuntu 16.04, which has two network connections, i.e wireless and USB/Ethernet adapter.
 One connection should have access to the internet (public),
 while the other connection should be to a dedicated network (private) containing the DGX to be provisioned.

Download the DGX Server ISO from the Enterprise Support Portal: https://nvidia-esp.custhelp.com

*Currently tested with DGX Server 3.1.2 170902 f8777e*

Place the ISO in the user home directory, e.g. `${HOME}/DGXServer-3.1.2.170902_f8777e.iso`

Run the *install_prereqs.sh* script on the Ubuntu 16.04 Linux laptop:

```console
./install_prereqs.sh
```

DGXie: PXE Boot DGX Install Environment - container components
===

DGXie is a Docker container application for remotely installing the official DGX Server operating system over the network

DGXie contains:
 * DHCP server
  * Provides PXE boot environment and DGX network settings
 * TFTP server
  * Provides PXE bootstrap files
 * FTP server
  * Provides a repo for the official DGX install ISO
 * HTTP server
  * Provides additional files such as a modified install pre-seed
 * NAT setup
  * Provides internet access to the DGX network through the system running DGXie
 * REST API
  * Provides list of host IP addresses from DHCP leases

DGXie should be run on a system connected to a network of DGX servers.
 The DGX servers are set to boot from the network interface connected to this network and will present a menu of boot options.
 Current boot options are to boot to the local disk (default) or to install the DGX operating system on the DGX.
 __There are no additional prompts after the menu, and the DGX will be completely erased during the install process.__

## Network topology

(public network)------[DGXie system]------(private network)------[DGX server systems]

The computer running this container can be on either a single network or two networks (public/private).

The container will attempt to set up NAT routing from a private to public subnet.

## Prerequisites

The computer running DGXie needs Docker and should be capable of running IPtables for NAT to work (Linux)

Download the DGX Server ISO from the Enterprise Support Portal: https://nvidia-esp.custhelp.com

Disable the boot order update timeout (required):

```console
# disable IPMI boot device selection 60s timeout
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x00 0x08 0x03 0x08
```

Set your DGX to boot from the network (PXE) for the next boot only:

```console
# set boot device to PXE, EFI, next boot only. Needed when defaulting to install vs boot local disk
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> chassis bootdev pxe options=efiboot
```

### Optional/Misc

You can also run the IPMI commands directly on the DGX via `ipmitool`:

```console
sudo ipmitool raw ...
```

To set the DGX to boot from disk first:

```console
# set boot device to first disk, EFI, persistent
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x00 0x08 0x05 0xe0 0x08 0x00 0x00 0x00
```

You can set the DGX to boot from the network every time, but if DGXie is set to default to install, this can create a re-install loop

```console
# set boot device to PXE, EFI, persistent
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x00 0x08 0x05 0xe0 0x04 0x00 0x00 0x00
```

## Setup and running

Mount the DGX Server ISO as a volume when running the container.

*Tested with DGX Base OS 3.1.2*

```console
sudo mkdir -p /mnt/3.1.2
sudo mount -o loop DGXServer-3.1.2.170902_f8777e.iso /mnt/3.1.2
```

Add an IP to your private interface (DGX network) if required

```console
sudo ip addr add 192.168.1.1/24 broadcast 192.168.1.255 dev ens192
```

Build and run the container

```console
docker build -t dgxie .
docker run -d --privileged --net=host -v /mnt/3.1.2:/iso:ro --name dgxie dgxie 
```

The `--privileged` and `--net=host` flags are required to manipulate IPTABLES on the host.

### DGXie configuration options

#### Provisioning host configuration

Specify DGXie server public network interface

```console
# default: eth0
-e HOST_INT_PUB=ens160
```

Specify DGXie server private network interface

```console
# default: eth1
-e HOST_INT_PRV=ens192
```

#### Provisioning network configuration

Options to configure the DHCP server subnet, these options are probably required

Specify DHCP/PXE server IP address (IP of machine running DGXie on DGX network)

```console
# default: 192.168.1.1
-e IP=10.0.0.1
```

Specify DHCP/PXE server network subnet

```console
# default: 192.168.1.0
-e NETWORK=10.0.0.0
```

Specify DHCP/PXE server subnet netmask

```console
# default: 255.255.255.0
-e NETMASK=255.255.255.0
```

Specify DHCP/PXE server subnet gateway

```console
# default: <value of IP> (192.168.1.1)
-e GATEWAY=10.0.0.254
```

Specify DHCP/PXE server DNS

```console
# default: 8.8.8.8, 8.8.4.4
-e DNS1=10.1.1.1 -e DNS2=10.2.2.2
```

Specify DHCP/PXE server lease range start/end

```console
# default: 192.168.1.2 192.168.1.254
-e DHCP_START=10.0.0.2 -e DHCP_END=10.0.0.254
```

#### DGX install options

These options are probably optional unless you're installing on something other than a DGX

Use a different interface on DGX clients

```console
# default: enp1s0f0
-e INT=eth0
```

Use a different disk for the root partition on DGX clients

```console
# default: sda
-e DISK=xvda
```

### Examples:

DGXie container running on a VM and provisioning DGX with the default subnet options. The VM has a public and private interface on two different VLANs.

```console
sudo docker run --rm -ti --net=host --privileged -v /mnt/3.1.2:/iso:ro -e HOST_INT_PUB=ens160 -e HOST_INT_PRV=ens192 --name dgxie dgxie
```

Attach to a running container:

```console
docker exec -ti dgxie /bin/sh
```

Show current DGX boot flags:

```console
sudo ipmitool chassis bootparam get 0x05
```

## Default user/pass

DGX installations will default to these login credentials:

user: dgxuser

pass: DgxUser123

## REST API

DGXie will output a list of uniq IP address of DGX-1 servers via REST API. Adjust `localhost` to the host running DGXie if not running from the same machine:

```console
curl http://localhost/hosts
```

DHCPD lease file parse script source: https://askubuntu.com/questions/219609/how-do-i-show-active-dhcp-leases
