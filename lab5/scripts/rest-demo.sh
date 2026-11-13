#!/usr/bin/env bash
set -euo pipefail
STUDENT=${STUDENT:-zakourcev}
N=${N:-37}
HQ=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "clab-${STUDENT}-l5-hq")
: "${HQ:?No HQ management address}"
if [[ -z "${ROS_PASSWORD:-}" ]]; then
  read -r -s -p "RouterOS admin password (will not echo): " ROS_PASSWORD
  echo
fi
base="http://${HQ}/rest"
auth="admin:${ROS_PASSWORD}"
echo "== GET /system/identity =="
curl -fsS -u "$auth" "$base/system/identity" | jq .
echo "== GET /ip/address =="
curl -fsS -u "$auth" "$base/ip/address" | jq '.[] | {address,interface}'
echo "== GET BGP sessions =="
curl -fsS -u "$auth" "$base/routing/bgp/session" | jq .
echo "== PUT address list lab =="
curl -fsS -u "$auth" -X PUT "$base/ip/firewall/address-list" -H 'content-type: application/json'   -d "{\"list\":\"lab\",\"address\":\"192.0.2.${N}\",\"comment\":\"${STUDENT}\"}" | jq .
ID=$(curl -fsS -u "$auth" "$base/ip/firewall/address-list?list=lab" | jq -r --arg ip "192.0.2.${N}" '[.[]|select(.address==$ip)][0][".id"]')
if [[ -z "$ID" || "$ID" == null ]]; then echo 'Cannot find created entry' >&2; exit 1; fi
echo "== PATCH comment =="
curl -fsS -u "$auth" -X PATCH "$base/ip/firewall/address-list/$ID"   -H 'content-type: application/json' -d '{"comment":"patched by REST"}' | jq .
echo "== DELETE address list entry =="
curl -sS -u "$auth" -X DELETE "$base/ip/firewall/address-list/$ID" -o /dev/null -w 'HTTP %{http_code}\n'
