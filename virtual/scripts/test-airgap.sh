#!/bin/bash
# Simple script to firewall off connections to the Internet for airgap testing

# Allow traffic to local IPs
iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -d 127.0.0.1 -j ACCEPT

# Otherwise drop outgoing traffic
iptables -P OUTPUT DROP
