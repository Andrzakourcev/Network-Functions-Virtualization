#!/usr/bin/env bash
# Итоговый блок для ЛР6. Нужны запущенный стенд и настроенные обе цепочки через fw2.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/settings.sh"
cd "$HERE" || exit 1
HOST="10.${N}.6.100"
FW_PORT=$((8000 + N))
C1="clab-${STUDENT}-l6-client1"
C2="clab-${STUDENT}-l6-client2"
FW2="clab-${STUDENT}-l6-fw2"
SH="clab-${STUDENT}-l6-shaper1"

printf '\n========================================\n'
printf 'Lab 6 completed: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf 'Student: %s@%s\n' "$(whoami)" "$(hostname)"
printf 'STUDENT=%s N=%s\n' "$STUDENT" "$N"
printf '========================================\n'

echo '=== VNF STATUS ==='
"$HERE/vnfm.sh" list

echo '=== SFC CHAINS ==='
grep 'name:.*-c' "$HERE/vnffg.yaml"

echo '=== OPENFLOW STATISTICS ==='
python3 "$HERE/nfvo.py" show "$HERE/vnffg.yaml" | head -26

echo '=== FW2 COUNTERS ==='
docker exec "$FW2" nft list ruleset | grep counter

echo '=== CLIENT HTTP ==='
docker exec "$C1" curl -s -o /dev/null -w 'client1 HTTP: %{http_code}\n' "http://${HOST}/"
docker exec "$C2" curl -s -o /dev/null -w 'client2 HTTP: %{http_code}\n' "http://${HOST}/"

echo '=== BLOCKED TCP PORT ==='
# curl exit 28 (timeout) ожидается для DROP и не должен останавливать скрипт.
docker exec "$C1" curl -s -m 3 -o /dev/null -w 'blocked port HTTP: %{http_code}\n' "http://${HOST}:${FW_PORT}/" || true

echo '=== SHAPER ==='
docker exec "$SH" tc -s qdisc show dev eth2

echo '=== IPERF3 FORWARD (MSS 1200) ==='
docker exec "$C1" iperf3 -c "$HOST" -t 3 -M 1200 -l 1200 | tail -7
