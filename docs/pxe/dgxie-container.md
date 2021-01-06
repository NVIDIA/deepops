# DGXIE

DGXie is an all-in-one container for DHCP, DNS, and PXE, specifically tailored to the DGX Base OS.

## Download DGX ISO

You will need to download the official DGX Base OS ISO image to your provisioning machine. The latest DGX Base OS is available via the NVIDIA Entperprise Support Portal (ESP).

Update the `DATA_DIR` specified in `config/pxe/env` and copy the DGX Base OS ISO there.

## Configure

Configuration information for DGXie is located in `config/pxe`. 

Update the `config/pxe/dnsmasq.extra.conf` with additional options, such as assigning static IPs by MAC address.

DGXie uses docker-compose to build and run. The `src/containers/dgxie/docker-compose-yml` file consumes several environment variables that are defined in `config/pxe/env`. Changes to the DHCP range, network used for serving up PXE files, and other values can be updated there. Be sure to update the `eth1` and `eth0` values to match your machine interfaces or the DGXie will fail to start.

   > Note: This assumes you have run the setup.sh script. If you have not, you must manually copy the example config and install docker/docker-compopse.

## Deploy DGXie container

```sh
./scripts/pxe/build_and_restart_dgxie.sh
```

## Testing the DGXie PXE service

If the default HTTP_PORT or machines.json file have not been changed, the below curl call should verify that the PXE API is responding:

```sh
curl localhost:13370/v1/boot/d8:c4:97:00:00:00
```

## PXE booting the DGX

The DGX servers can be PXE booted manually through the console. The DeepOps repo also provides the `dgxctl.sh` tool to automate this process using IPMI.

Update the `config/pxe/ipmi_host_list` file with a list of BMC IPs.
Update the `config/pxe/ipmi.conf` file with the proper username and password.

Run:

```sh
./scripts/pxe/dgxctl.sh -i
```

   > Note: This tool assumes all DGX systems are configured with the same username and password.


## Making updates

To make configuration changes or ISO updates, update the config files or ISO followed by re-running `./scripts/pxe/build_and_restart_dgxie.sh`. This will tear down the old DGXie and start a new one with the configuration changes.

Updates to the machines.json file do not require a restart.
