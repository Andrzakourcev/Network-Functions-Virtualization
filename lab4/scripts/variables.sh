# Выполнять из bash: source scripts/variables.sh
export STUDENT=zakourcev
export N=37
export ISU=408637
export ODL=http://10.104.37.100:8181
odl_get() { curl -s -u admin:admin "$ODL/rests/data/$1" | jq .; }
put_flow() { # put_flow <DPID> <flow-id> <json-file>
  curl -s -u admin:admin -X PUT -H 'Content-Type: application/json' -d @"$3" \
    -o /dev/null -w "PUT $2: %{http_code}\n" \
    "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$1/flow-node-inventory:table=0/flow=$2"
}
del_flow() { # del_flow <DPID> <flow-id>
  curl -s -u admin:admin -X DELETE -o /dev/null -w "DELETE $2: %{http_code}\n" \
    "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$1/flow-node-inventory:table=0/flow=$2"
}
