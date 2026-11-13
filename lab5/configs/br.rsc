# 2026-11-13 20:59:35 by RouterOS 7.23.8
# system id = XBzsTdf1TjK
#
/interface ethernet set [ find default-name=ether1 ] disable-running-check=no
/interface ethernet set [ find default-name=ether2 ] disable-running-check=no
/interface ethernet set [ find default-name=ether3 ] disable-running-check=no
/interface wireguard add listen-port=13037 mtu=1420 name=wg-hq
/interface list add comment=clab-mgmt name=clab-management
/interface list add comment=clab-mgmt exclude=clab-management include=static name=clab-discovery
/ip vrf add comment=clab-mgmt interfaces=ether1 name=mgmt
/ip neighbor discovery-settings set discover-interface-list=clab-discovery
/interface list member add comment=clab-mgmt interface=ether1 list=clab-management
/interface wireguard peers add allowed-address=10.37.254.1/32,10.37.100.0/24 endpoint-address=100.64.1.2 endpoint-port=13037 interface=wg-hq name=peer1 persistent-keepalive=25s public-key="FtkKMN6BPxy0maWvFlwB4yFiAwI8YHlDX4nUy+igiDE="
/ip address add address=10.105.37.6/24 comment=clab-mgmt interface=ether1 network=10.105.37.0
/ip address add address=100.64.2.2/30 comment=WAN interface=ether2 network=100.64.2.0
/ip address add address=10.37.200.1/24 comment=LAN interface=ether3 network=10.37.200.0
/ip address add address=10.37.254.2/30 interface=wg-hq network=10.37.254.0
/ip dhcp-client add disabled=yes interface=ether1 name=client1
/ip firewall nat add action=masquerade chain=srcnat comment="branch -> Internet" out-interface=ether2
/ip route add comment=clab-mgmt dst-address=0.0.0.0/0 gateway=10.105.37.1@mgmt routing-table=mgmt
/ip route add comment=ISP dst-address=0.0.0.0/0 gateway=100.64.2.1
/ip route add dst-address=10.37.100.0/24 gateway=wg-hq
/ip service set ssh vrf=mgmt
/ip service set telnet vrf=mgmt
/ip service set www vrf=mgmt
/ip service set www-ssl vrf=mgmt
/ip service set winbox vrf=mgmt
/ip service set api vrf=mgmt
/ip service set api-ssl vrf=mgmt
/ipv6 nd add interface=ether1 ra-lifetime=none
/snmp set vrf=mgmt
/system identity set name=br-zakourcev
