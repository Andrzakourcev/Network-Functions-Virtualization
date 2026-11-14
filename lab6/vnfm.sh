#!/usr/bin/env bash
# Учебный VNFM: управление жизненным циклом экземпляров VNF и их подключением к OVS.
#   ./vnfm.sh configure   <имя> <тип fw|shaper>                    # настроить VNF из топологии
#   ./vnfm.sh instantiate <имя> <тип fw|shaper> <порт_in> <порт_out> # создать новый экземпляр (scale-out)
#   ./vnfm.sh terminate   <имя> <порт_in> <порт_out>                # удалить экземпляр
#   ./vnfm.sh list                                                  # экземпляры VNF лаборатории
set -euo pipefail
: "${STUDENT:?export STUDENT}" "${N:?export N}"
LAB="${STUDENT}-l6"
SW="clab-${LAB}-sw"
IMAGE="lab-tools:1.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
export FW_PORT=$((8000 + N))

configure_vnf() {   # $1 - контейнер, $2 - тип
  # прозрачная VNF «в разрыв» (bump-in-the-wire): мост eth1 <-> eth2
  docker exec "$1" sh -c '
    ip link show br0 >/dev/null 2>&1 || ip link add br0 type bridge
    ip link set eth1 master br0 && ip link set eth2 master br0
    for i in eth1 eth2 br0; do ip link set "$i" up; done
    ethtool -K eth1 tx off >/dev/null 2>&1; ethtool -K eth2 tx off >/dev/null 2>&1; true'
  case "$2" in
    fw)
      # Для WSL2: bridge traffic -> nftables table ip via br_netfilter.
      # Исходные правила table bridge сохранены отдельно как fw-rules.bridge.nft.
      if grep -Eq '^[[:space:]]*table[[:space:]]+ip[[:space:]]+vnf_fw' "$HERE/vnf/fw-rules.nft"; then
        docker exec "$1" sh -c           'sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null' || {
          echo 'br_netfilter недоступен: проверьте ядро и net.bridge.bridge-nf-call-iptables' >&2
          exit 1
        }
      fi
      envsubst < "$HERE/vnf/fw-rules.nft" | docker exec -i "$1" nft -f - ;;
    shaper) docker exec "$1" tc qdisc replace dev eth2 root tbf rate "$((10 + N % 10))mbit" burst 32kbit latency 400ms ;;
    *)      echo "неизвестный тип VNF: $2" >&2; exit 1 ;;
  esac
  docker exec "$1" sh -c 'echo "--- $(hostname)"; ip -br link show master br0; nft list ruleset 2>/dev/null | head -20; tc qdisc show dev eth2'
}

attach_port() {     # $1 - номер порта OVS
  docker exec "$SW" sh -c "ethtool -K eth$1 tx off >/dev/null 2>&1; \
    ovs-vsctl --may-exist add-port br0 eth$1 -- set interface eth$1 ofport_request=$1"
}

case "${1:-}" in
  configure)
    configure_vnf "clab-${LAB}-$2" "$3" ;;
  instantiate)
    name=$2; type=$3; pin=$4; pout=$5; c="clab-${LAB}-${name}"
    docker run -d --name "$c" --hostname "$name" --network none --privileged \
      --label "nfv-lab=${LAB}" --label "vnf-type=${type}" "$IMAGE" >/dev/null
    containerlab tools veth create -a "${c}:eth1" -b "${SW}:eth${pin}"
    containerlab tools veth create -a "${c}:eth2" -b "${SW}:eth${pout}"
    attach_port "$pin"; attach_port "$pout"
    configure_vnf "$c" "$type"
    echo "VNF ${name} (${type}) создан, порты OVS ${pin}/${pout}" ;;
  terminate)
    name=$2; pin=$3; pout=$4
    docker rm -f "clab-${LAB}-${name}" >/dev/null
    docker exec "$SW" ovs-vsctl --if-exists del-port br0 "eth${pin}" -- --if-exists del-port br0 "eth${pout}"
    echo "VNF ${name} удалён" ;;
  list)
    docker ps -a --filter "name=clab-${LAB}-" --format 'table {{.Names}}\t{{.Status}}\t{{.Label "vnf-type"}}' ;;
  *)
    sed -n '2,7p' "$0"; exit 1 ;;
esac
