#!/usr/bin/env bash
# Run from lab4 directory: bash scripts/push-flows.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/variables.sh
for spec in \
  "1:s1-1to2" "1:s1-2to1" \
  "2:s2-to-h2-ip" "2:s2-to-h2-arp" \
  "2:s2-to-h3-ip" "2:s2-to-h3-arp" \
  "2:s2-1to2" "2:s2-3to2"
do
    dpid=${spec%%:*}
    name=${spec#*:}
    id="$STUDENT-$name"
    url="$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$dpid/flow-node-inventory:table=0/flow=$id"
    echo "Installing $id on s$dpid ..."
    http=$(curl -sS --connect-timeout 8 --max-time 25 -u admin:admin -X PUT \
      -H 'Content-Type: application/json' \
      --data-binary "@flows/$name.json" -o /tmp/odl-flow-response-$$ -w '%{http_code}' "$url")
    echo "  HTTP $http"
    if [[ "$http" != "201" && "$http" != "204" && "$http" != "200" ]]; then
      cat /tmp/odl-flow-response-$$; echo
      rm -f /tmp/odl-flow-response-$$
      exit 1
    fi
done
rm -f /tmp/odl-flow-response-$$
echo "All eight proactive flows installed."
