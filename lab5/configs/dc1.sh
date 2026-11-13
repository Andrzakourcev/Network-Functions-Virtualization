#!/usr/bin/env bash
# Run inside dc1 SONiC (or pipe using: docker exec -i clab-zakourcev-l5-dc1 bash < configs/dc1.sh)
# Addresses and AS are personalized for N=37.
set -e
supervisorctl start zebra mgmtd staticd bgpd >/dev/null 2>&1 || true
config interface startup Ethernet0
config interface startup Ethernet4
config interface ip add Ethernet0 10.37.100.1/24
config interface ip add Ethernet4 10.37.1.1/30
# Management default route is intentionally removed before BGP default installation
ip route del default dev eth0 || true
vtysh <<'EOF'
configure terminal
router bgp 65037
 bgp router-id 10.37.1.1
 no bgp ebgp-requires-policy
 neighbor 10.37.1.2 remote-as 65137
 address-family ipv4 unicast
  network 10.37.100.0/24
 exit-address-family
end
write memory
EOF
