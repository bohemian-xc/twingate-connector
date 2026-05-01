#!/usr/bin/env bash
# macvlan-shim.sh
# Creates a host-side macvlan shim so the host can reach containers on an
# existing Docker macvlan network. This script DOES NOT create the Docker
# network; run `docker compose -f docker-twingate-vlan.yml up -d` first.
#
# Usage : sudo ./macvlan-shim.sh PARENT NAME HOST_IP
# Example : sudo ./macvlan-shim.sh eth0.10 vlan10_net 192.168.10.50/24

set -euo pipefail

# Accept either 3 args (PARENT NAME HOST_IP) or 5 args (PARENT NAME SUBNET GATEWAY HOST_IP)
if [ "$#" -eq 3 ]; then
  PARENT="$1"
  NAME="$2"
  HOST_IP="$3"
else
  echo "Usage: $0 PARENT NAME HOST_IP"
  exit 2
fi

# Check that the named Docker network exists (expect compose to create it)
if ! sudo docker network inspect "${NAME}" >/dev/null 2>&1; then
  echo "Docker network '${NAME}' not found. Run 'docker compose -f docker-twingate-vlan.yml up -d' first to create the network."
  exit 3
fi

# Create host-side macvlan interface so the host can reach macvlan containers
SHIM_IF="macvlan-shim"
if ip link show "${SHIM_IF}" >/dev/null 2>&1; then
  echo "${SHIM_IF} already exists, reusing it."
else
  sudo ip link add "${SHIM_IF}" link "${PARENT}" type macvlan mode bridge
fi

sudo ip addr flush dev "${SHIM_IF}" || true
sudo ip addr add "${HOST_IP}" dev "${SHIM_IF}"
sudo ip link set "${SHIM_IF}" up

echo "Host macvlan shim '${SHIM_IF}' configured with ${HOST_IP}."

echo "Done. You can now reach containers on Docker network '${NAME}' from the host."
