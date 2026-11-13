# 2026-11-13 20:59:30 by RouterOS 7.23.8
# system id = s0cDAAM0TAM
#
/interface ethernet set [ find default-name=ether1 ] disable-running-check=no
/interface ethernet set [ find default-name=ether2 ] disable-running-check=no
/interface ethernet set [ find default-name=ether3 ] disable-running-check=no
/interface wireguard add listen-port=13037 mtu=1420 name=wg-br
/interface list add comment=clab-mgmt name=clab-management
/interface list add comment=clab-mgmt exclude=clab-management include=static name=clab-discovery
/ip vrf add comment=clab-mgmt interfaces=ether1 name=mgmt
/routing bgp instance add as=65137 name=hq
/ip neighbor discovery-settings set discover-interface-list=clab-discovery
/interface list member add comment=clab-mgmt interface=ether1 list=clab-management
/interface wireguard peers add allowed-address=10.37.254.2/32,10.37.200.0/24 endpoint-address=100.64.2.2 endpoint-port=13037 interface=wg-br name=peer1 persistent-keepalive=25s public-key="lGC92yKMuxv7eUY19K/pCgJV3Kh7t3pNb5itAJZiXXQ="
/ip address add address=10.105.37.2/24 comment=clab-mgmt interface=ether1 network=10.105.37.0
/ip address add address=10.37.1.2/30 comment="to DC" interface=ether2 network=10.37.1.0
/ip address add address=100.64.1.2/30 comment=WAN interface=ether3 network=100.64.1.0
/ip address add address=10.37.254.1/30 interface=wg-br network=10.37.254.0
/ip dhcp-client add disabled=yes interface=ether1 name=client1
/ip firewall address-list add address=10.37.200.0/24 list=to-dc
/ip firewall filter add action=accept chain=input comment="input: established" connection-state=established,related
/ip firewall filter add action=drop chain=input connection-state=invalid
/ip firewall filter add action=accept chain=input protocol=icmp
/ip firewall filter add action=accept chain=input comment="mgmt (containerlab)" in-interface=mgmt
/ip firewall filter add action=accept chain=input comment="BGP from DC" dst-port=179 in-interface=ether2 protocol=tcp
/ip firewall filter add action=accept chain=input comment=WireGuard dst-port=13037 protocol=udp
/ip firewall filter add action=drop chain=input comment="drop other from WAN" in-interface=ether3
/ip firewall filter add action=accept chain=forward comment="forward: established" connection-state=established,related
/ip firewall filter add action=drop chain=forward connection-state=invalid
/ip firewall filter add action=accept chain=forward comment="DC -> Internet" in-interface=ether2 out-interface=ether3
/ip firewall filter add action=accept chain=forward comment="branch -> DC" in-interface=wg-br out-interface=ether2
/ip firewall filter add action=accept chain=forward comment="DC -> branch" in-interface=ether2 out-interface=wg-br
/ip firewall filter add action=drop chain=forward comment="default deny"
/ip firewall nat add action=masquerade chain=srcnat comment="inside -> Internet" out-interface=ether3
/ip route add comment=clab-mgmt dst-address=0.0.0.0/0 gateway=10.105.37.1@mgmt routing-table=mgmt
/ip route add comment=ISP dst-address=0.0.0.0/0 gateway=100.64.1.1
/ip route add dst-address=10.37.200.0/24 gateway=wg-br
/ip service set ssh vrf=mgmt
/ip service set telnet vrf=mgmt
/ip service set www vrf=mgmt
/ip service set www-ssl vrf=mgmt
/ip service set winbox vrf=mgmt
/ip service set api vrf=mgmt
/ip service set api-ssl vrf=mgmt
/ipv6 nd add interface=ether1 ra-lifetime=none
/routing bgp connection add instance=hq local.role=ebgp name=to-dc output.default-originate=if-installed .network=to-dc remote.address=10.37.1.1 .as=65037
/snmp set vrf=mgmt
/system identity set name=hq-zakourcev
