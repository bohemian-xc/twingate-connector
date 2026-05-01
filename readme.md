
# Twingate Connector on Raspberry Pi with VLAN + macvlan

This guide explains how to configure a Raspberry Pi to host containers on a VLAN and expose containers directly on your LAN using a Docker macvlan network. It includes:

- VLAN setup on Raspberry Pi
- A reusable macvlan "shim" script to make host <-> container networking workable
- How to deploy the Twingate Connector using the provided Docker Compose file

Follow the steps below carefully. Commands assume a Linux shell on the Raspberry Pi and that Docker (Docker Engine + Compose) is installed.

**Prerequisites**:
- Raspberry Pi OS with network access
- Root or sudo privileges on the Pi
- Docker Engine and Docker Compose installed

**Notes**: Use the VLAN IDs, IP addresses, and parent interface names applicable to your environment. The example below uses `eth0` as the physical interface and VLAN ID `10`.

## 1. Setting up VLAN on Raspberry Pi

This section follows the steps from the Engineer's Workshop guide to create VLAN virtual NICs and configure IP addressing.

Prerequisites:

- A managed switch port configured as a trunk/hybrid with the VLANs you need
- Physical NIC name on the Pi (e.g., `eth0`)

1) Install the VLAN package

```bash
sudo apt update
sudo apt install -y vlan
```

2) Create virtual NICs

Create the file `/etc/network/interfaces.d/vlans` and add a stanza for each VLAN. Example for VLAN 10:

```
auto eth0.10
iface eth0.10 inet manual
	vlan-raw-device eth0
```

By convention the virtual NIC is named `<physicalNIC>.<PVID>` (for example, `eth0.10`). Add additional blocks for more VLANs.

3) Configure addressing (static example)

Edit `/etc/dhcpcd.conf` and add IP configuration for each interface you want to set statically. Example:

```
# example static IP configuration

interface eth0
	static ip_address=10.0.20.125/24

interface eth0.10
	static ip_address=10.0.10.125/24
	static routers=10.0.10.1
	static domain_name_servers=1.1.1.1
```

If you use DHCP for a VLAN virtual NIC, you can skip the static block for that interface.

4) Apply changes

Restart networking or reboot:

```bash
sudo systemctl restart networking
# or
sudo reboot
```

5) Verify

Confirm both addresses are present:

```bash
hostname -I
# expected output example: 10.0.20.125 10.0.10.125
```

If you need to enable the `8021q` kernel module explicitly, add it to `/etc/modules` so it loads at boot:

```bash
echo 8021q | sudo tee -a /etc/modules
sudo modprobe 8021q
```

Notes:

- Replace `eth0`, VLAN IDs and IP addresses with values for your network.
- If your Pi uses a different init/system (or a GUI network manager), adapt these steps accordingly.

## 2. Setting up Twingate Connector (Docker Compose)

The provided compose file `docker-twingate-vlan.yml` in this folder defines a service `twingate_connector` and a macvlan network `vlan10_net`. It expects environment variables to be defined for sensitive values and for the network parent.

Important environment variables (set in your shell or an `.env` file):

- `TG_LABEL_HOSTNAME` — container name / hostname
- `VLAN10_PARENT` — parent interface for macvlan (e.g., `eth0.10`)
- `VLAN10_SUBNET` — subnet for the macvlan (e.g., `192.168.10.0/24`)
- `VLAN10_GATEWAY` — gateway (e.g., `192.168.10.1`)
- `VLAN10_IPADDRESS` — desired static IP for the connector (optional; can also use DHCP in some setups)
- `TG_NETWORK`, `TG_ACCESS_TOKEN`, `TG_REFRESH_TOKEN` — Twingate-specific config values

Example `.env` file (fill with your values):

```
TG_LABEL_HOSTNAME=twingate-connector
VLAN10_PARENT=eth0.10
VLAN10_SUBNET=192.168.10.0/24
VLAN10_GATEWAY=192.168.10.1
VLAN10_IPADDRESS=192.168.10.60
TG_NETWORK=your-twingate-network
TG_ACCESS_TOKEN=...
TG_REFRESH_TOKEN=...
```

Bring up the connector:

```bash
# start the connector using docker compose (this will create the named network)
docker compose -f docker-twingate-vlan.yml up -d

# view logs
docker compose -f docker-twingate-vlan.yml logs -f twingate_connector
```

Notes:

- The Compose file creates `vlan10_net` using `driver: macvlan` and `parent: ${VLAN10_PARENT}`. The parent must exist and be the VLAN interface (e.g., `eth0.10`).
- After the compose stack brings up the network, run the host shim so the Pi can reach containers on that macvlan network (instructions below).
- If you want containers to get static addresses, set `VLAN10_IPADDRESS` in the `.env` and ensure it does not collide with other addresses in the subnet.

## 3. Set up a macvlan shim

Purpose: Docker macvlan places containers on the same L2 network as the parent interface, but by default the host cannot talk to containers on a macvlan network. A host-side macvlan shim interface gives the host an address on the macvlan network so you can reach containers directly from the Pi.

This repository includes `macvlan-shim.sh`. Unlike earlier versions, `macvlan-shim.sh` will not create the Docker network — it checks that the named Docker network already exists and then creates/configures a host shim interface so the host can reach containers.

Usage (after you have brought the Compose stack up so the Docker network exists):

```bash
# make executable once
sudo chmod +x macvlan-shim.sh

# run the shim script
# It accepts either 3 args: PARENT NAME HOST_IP
# or the original 5 args for compatibility: PARENT NAME SUBNET GATEWAY HOST_IP
sudo ./macvlan-shim.sh eth0.10 vlan10_net 192.168.10.50/24
```

The script will exit with a helpful message if the Docker network `${NAME}` is not present (run `docker compose -f docker-twingate-vlan.yml up -d` first).

Tips:
- Use `parent` equal to your VLAN sub-interface (e.g., `eth0.10`).
- Persist the shim via a `systemd` unit if you want it recreated at boot.
- Ensure firewall rules allow traffic between the host shim and macvlan container addresses.

## Troubleshooting

- Container cannot reach gateway: confirm `parent` and subnet are correct, and VLAN sub-interface is up on the Pi.
- Host cannot reach container: ensure the host shim interface exists and has an IP on the macvlan subnet. Check `ip addr` and `ip link`.
- Docker permission/network errors: ensure Docker Engine is installed and you have appropriate privileges.

## Cleanup

To remove the docker network and host shim:

```bash
docker compose -f docker-twingate-vlan.yml down
docker network rm vlan10_net || true
sudo ip link set macvlan-shim down || true
sudo ip link delete macvlan-shim || true
```

## References

- Raspberry Pi VLAN setup (guide used for steps and best practices): https://engineerworkshop.com/blog/raspberry-pi-vlan-how-to-connect-your-rpi-to-multiple-networks/
