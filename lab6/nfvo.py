#!/usr/bin/env python3
"""Учебный мини-NFVO: читает описание цепочек (VNFFG) из YAML и программирует
OVS через OpenDaylight (RESTCONF RFC 8040).

  python3 nfvo.py apply  vnffg.yaml   # создать/обновить потоки всех цепочек
  python3 nfvo.py show   vnffg.yaml   # потоки и счётчики пакетов
  python3 nfvo.py delete vnffg.yaml   # удалить все потоки, созданные nfvo (id начинается с sfc-)

Роль в архитектуре ETSI NFV MANO: упрощённый NFVO, который по описанию VNFFG
программирует сеть через SDN-контроллер (OpenDaylight).
"""
import os
import sys

import requests
import yaml

PRIORITY = 300


def load(path):
    """YAML с подстановкой переменных окружения (${N}, ${STUDENT})."""
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(os.path.expandvars(f.read()))


class Odl:
    def __init__(self, cfg):
        c = cfg["controller"]
        self.base = c["url"].rstrip("/") + "/rests/data/opendaylight-inventory:nodes"
        self.auth = (c["user"], c["password"])
        self.node = cfg["switch"]                       # например openflow:1
        self.node_q = self.node.replace(":", "%3A")

    def table_url(self, flow_id=None):
        url = f"{self.base}/node={self.node_q}/flow-node-inventory:table=0"
        return url + (f"/flow={flow_id}" if flow_id else "")

    def put_flow(self, flow):
        r = requests.put(self.table_url(flow["id"]), auth=self.auth, timeout=10,
                         json={"flow-node-inventory:flow": [flow]})
        r.raise_for_status()
        return r.status_code

    def list_flows(self, content="config"):
        r = requests.get(self.table_url() + f"?content={content}", auth=self.auth, timeout=10)
        if r.status_code == 409:                        # таблица ещё пустая
            return []
        r.raise_for_status()
        return r.json()["flow-node-inventory:table"][0].get("flow", [])

    def delete_flow(self, flow_id):
        requests.delete(self.table_url(flow_id), auth=self.auth, timeout=10).raise_for_status()


def make_flow(flow_id, in_port, node, out_port, ip, ip_field, arp_field):
    """Два потока на один переход: IPv4 и ARP. ip_field/arp_field - чем матчим клиента."""
    out = {"instructions": {"instruction": [{"order": 0, "apply-actions": {"action": [
        {"order": 0, "output-action": {"output-node-connector": str(out_port)}}]}}]}}
    ipv4 = {"id": flow_id + "-ip", "table_id": 0, "priority": PRIORITY,
            "match": {"in-port": f"{node}:{in_port}",
                      "ethernet-match": {"ethernet-type": {"type": 2048}},
                      ip_field: f"{ip}/32"}, **out}
    arp = {"id": flow_id + "-arp", "table_id": 0, "priority": PRIORITY,
           "match": {"in-port": f"{node}:{in_port}",
                     "ethernet-match": {"ethernet-type": {"type": 2054}},
                     arp_field: f"{ip}/32"}, **out}
    return [ipv4, arp]


def build_flows(cfg):
    node, vnfs, ends = cfg["switch"], cfg["vnfs"], cfg["endpoints"]
    flows = []
    for ch in cfg["chains"]:
        src = ends[ch["from"]]
        dst = ends[ch["to"]]
        hops = [vnfs[name] for name in ch["path"]]
        # прямое направление: клиент -> VNF1.in, VNF1.out -> VNF2.in, ..., VNFn.out -> сервер
        fwd = [src["port"]] + [p for h in hops for p in (h["in"], h["out"])] + [dst["port"]]
        for i in range(0, len(fwd), 2):
            flows += make_flow(f"sfc-{ch['name']}-fwd{i // 2}", fwd[i], node, fwd[i + 1],
                               src["ip"], "ipv4-source", "arp-source-transport-address")
        # обратное направление: тот же путь в обратном порядке, матч по адресу клиента как получателя
        rev = list(reversed(fwd))
        for i in range(0, len(rev), 2):
            flows += make_flow(f"sfc-{ch['name']}-rev{i // 2}", rev[i], node, rev[i + 1],
                               src["ip"], "ipv4-destination", "arp-target-transport-address")
    return flows


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("apply", "show", "delete"):
        print(__doc__)
        sys.exit(1)
    cmd, cfg = sys.argv[1], load(sys.argv[2])
    odl = Odl(cfg)
    if cmd == "apply":
        wanted = build_flows(cfg)
        wanted_ids = {f["id"] for f in wanted}
        for f in wanted:
            odl.put_flow(f)
        stale = [f["id"] for f in odl.list_flows() if f["id"].startswith("sfc-") and f["id"] not in wanted_ids]
        for fid in stale:                               # удаляем потоки цепочек, которых больше нет в YAML
            odl.delete_flow(fid)
        print(f"applied: {len(wanted)} flows, removed stale: {len(stale)}")
    elif cmd == "show":
        for f in sorted(odl.list_flows("nonconfig"), key=lambda x: x.get("id", "")):
            st = f.get("opendaylight-flow-statistics:flow-statistics", {})
            m = f.get("match", {})
            print(f"{f.get('id', '?'):28} prio={f.get('priority')} in={m.get('in-port', '*'):14} "
                  f"pkts={st.get('packet-count', '0')}")
    elif cmd == "delete":
        ids = [f["id"] for f in odl.list_flows() if f["id"].startswith("sfc-")]
        for fid in ids:
            odl.delete_flow(fid)
        print(f"deleted: {len(ids)} flows")


if __name__ == "__main__":
    main()
