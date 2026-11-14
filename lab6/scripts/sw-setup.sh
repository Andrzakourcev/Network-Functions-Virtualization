#!/bin/sh
# Использование: docker exec -i -e ODL_IP=10.106.N.100 clab-<фамилия>-l6-sw sh < scripts/sw-setup.sh
set -e
ovs-vsctl --may-exist add-br br0 -- set bridge br0 datapath_type=netdev protocols=OpenFlow13 \
  fail-mode=secure other-config:datapath-id=0000000000000001 other-config:disable-in-band=true
for i in 1 2 3 4 5 6 7 8 9; do
  ip link show "eth$i" >/dev/null 2>&1 || continue      # eth5/eth6 появятся при scale-out
  ethtool -K "eth$i" tx off >/dev/null 2>&1 || true
  ovs-vsctl --may-exist add-port br0 "eth$i" -- set interface "eth$i" ofport_request=$i
done
ovs-vsctl set-controller br0 "tcp:${ODL_IP}:6653"
ovs-ofctl -O OpenFlow13 show br0 | grep -E "^ [0-9]+\("
