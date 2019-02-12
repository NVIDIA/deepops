PXE
===

Minimal containers for OS installation

## Requirements

  * Control machine connected to the same VLAN/subnet as target machines
  * Docker installed on control machine

## Working with an existing DHCP server

Modify `containers/pxe/docker-compose.yml`

Start the PXE server:

```sh
docker-compose -f containers/pxe/docker-compose.yml up -d pxe-ubuntu
```

## Working with no existing DHCP server

Modify `containers/pxe/docker-compose.yml`

Modify `containers/pxe/dhcp/dnsmasq.conf`

Start the DHCP and PXE servers:

```sh
docker-compose -f containers/pxe/docker-compose.yml up -d dhcp pxe-ubuntu
```
