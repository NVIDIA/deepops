PXE
===

Minimal containers for OS installation

## Requirements

  * Control machine connected to the same VLAN/subnet as target machines
  * Docker installed on control machine

## Installation Steps

This process should run from a Linux system on the same network segment as the target nodes.

1. Install docker.

   ```sh
   ./scripts/generic/install_docker.sh
   ```

2. (Optional) Start DHCP server.

   If you have an existing DHCP server, skip this step

   ```sh
   # Modify listen interface, DHCP range, and network gateway IP
   docker-compose -f src/containers/pxe/docker-compose.yml run -d dhcp dnsmasq -d --interface=ens192 --dhcp-range=192.168.1.100,192.168.1.199,7200 --dhcp-option=6,8.8.8.8 --dhcp-option=3,192.168.1.1
   ```

3. (Optional) Configure NAT routing.

   If you have an existing network gateway, skip this step

   ```sh
   # Set eth0 and eth1 to your public and private interfaces, respectively
   ./scripts/pxe/setup_nat.sh eth0 eth1
   ```

4. Start PXE server.

   ```sh
   docker-compose -f src/containers/pxe/docker-compose.yml up -d pxe
   ```

5. Install OS.

   Set servers to boot from the network for the next boot only (to avoid re-install loops) and reboot them to install the OS.

   The default credentials are:
   * Username: `ubuntu`
   * Password: `deepops`

## IPMI Command Reference

```sh
# Set to boot from disk, always
# Dell
chassis bootdev disk options=persistent
# DGX
raw 0x00 0x08 0x05 0xe0 0x08 0x00 0x00 0x00

# Set to boot from the network, next boot only
chassis bootdev pxe options=efiboot
```
