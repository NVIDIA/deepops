```sh
export HOST_INT_PUB=ens160
export HOST_INT_PRV=ens192
/sbin/iptables -t nat -A POSTROUTING -o ${HOST_INT_PUB} -j MASQUERADE
/sbin/iptables -A FORWARD -i ${HOST_INT_PUB} -o ${HOST_INT_PRV} -m state --state RELATED,ESTABLISHED -j ACCEPT
/sbin/iptables -A FORWARD -i ${HOST_INT_PRV} -o ${HOST_INT_PUB} -j ACCEPT
sysctl -w net.ipv4.ip_forward=1
```
