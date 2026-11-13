# Лабораторная №5 — MikroTik CHR как vCPE

Студент: Закоурцев Андрей, ИСУ 408637, `STUDENT=zakourcev`, `N=37`.

Источник требований — `labs/05-mikrotik-vcpe-multivendor.md` из учебного архива.

## Оборудование и IP

- srv1: `10.37.100.10/24`, шлюз `10.37.100.1`.
- dc1 (SONiC/FRR): `Ethernet0=10.37.100.1/24`; `Ethernet4=10.37.1.1/30`; AS `65037`.
- hq (RouterOS): `ether2=10.37.1.2/30`, `ether3=100.64.1.2/30`, `wg-br=10.37.254.1/30`; AS `65137`.
- isp (Linux): `eth1=100.64.1.1/30`, `eth2=100.64.2.1/30`, `lo=198.51.100.1/32`.
- br (RouterOS): `ether2=100.64.2.2/30`, `ether3=10.37.200.1/24`, `wg-hq=10.37.254.2/30`.
- pcb: `10.37.200.10/24`, шлюз `10.37.200.1`.
- WireGuard UDP `13037`.

## Скриншоты для отчёта

1. KVM, Docker, Containerlab и образы.
2. Развёрнутые шесть узлов Containerlab.
3. Identity и interfaces обеих CHR.
4. IP на HQ, BR и DC1 + ping WAN.
5. FRR BGP summary и маршрут по умолчанию.
6. RouterOS BGP session + route.
7. NAT: srv1 HTTP 200; ISP лог показывает `100.64.1.2`.
8. Firewall HQ: правила, статистика; ISP -> srv1 ping блокируется.
9. WireGuard: интерфейсы, peer handshake и counters на HQ/BR.
10. BGP: маршрут филиала `10.37.200.0/24` на DC1; pcb -> srv1 ping проходит.
11. ISP tcpdump: UDP WireGuard 13037 (не показываются внутренние IP-адреса).
12. REST API GET, PUT, PATCH, DELETE.
13. Экспорт конфигураций без паролей/секретов.
14. Финальная проверка с временем, логином, SSH, BGP, WG, ping и HTTP.

> Пароли, приватные ключи WireGuard, другие секреты не коммитить. REST HTTP используйте только на изолированном стенде.

## Развёртывание

- `lab5.clab.yml` — оригинальный вид из методички: `mikrotik_ros` + vrnetlab (нужен KVM/подготовленный образ).
- `lab5.clab.wsl.yml` — альтернативный современный `mikrotik_chr` + `mikrotik/chr:7.23.8` для Containerlab v0.82+, может работать без KVM через QEMU TCG, но медленнее. Этот способ не описан в учебной методичке; согласуйте с преподавателем, если необходима строгая идентичность стенда.

Выберите **один** topology-файл; не разворачивайте оба одновременно под одним именем лабораторной.
