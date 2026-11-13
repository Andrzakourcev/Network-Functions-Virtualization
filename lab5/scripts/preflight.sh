#!/usr/bin/env bash
set -u
echo '== LAB5 prereqs =='
echo 'KVM:'
if [[ -e /dev/kvm ]]; then ls -l /dev/kvm; else echo 'MISSING /dev/kvm: CHR requires KVM'; fi
echo 'CPU virtualization flags:'
grep -m1 -Eo 'vmx|svm' /proc/cpuinfo || true
echo 'Docker:'
docker info --format '{{.ServerVersion}}' 2>&1 || true
echo 'Containerlab:'
containerlab version 2>&1 || true
echo 'Required images:'
for image in sonic-course:202511 lab-tools:1.0 vrnetlab/mikrotik_routeros:7.23.8; do
  if docker image inspect "$image" >/dev/null 2>&1; then echo "OK: $image"; else echo "MISSING: $image"; fi
done
