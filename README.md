# meshmonitor-pi
![Version](https://img.shields.io/badge/version-0.3.3-blue) ![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-lightgrey) ![License](https://img.shields.io/badge/license-BSD--3--Clause-green)

A Docker deployment of [MeshMonitor](https://meshmonitor.org/) for Raspberry Pi — optimized for SD card longevity and hands-off operation.

## What's Included

| Container | Purpose |
|---|---|
| `meshmonitor` | Web dashboard — connects to Meshtastic nodes via TCP, serial, or BLE |

MQTT integration is available natively in MeshMonitor 4.0 via Dashboard → Sources → Add → MQTT. No sidecar needed.

Serial bridge is pre-stubbed in `docker-compose.yml` for future use — see [Adding a Serial Node](#adding-a-serial-node).

## Hardware

### Tested Configuration

| Component | Used |
|---|---|
| **Board** | Raspberry Pi 4 (4 GB RAM) |
| **SD card** | 32 GB Samsung Endurance Pro |
| **OS** | Raspberry Pi OS Lite 64-bit (bookworm) |
| **IP assignment** | DHCP reservation in router (no static config on Pi) |

### RAM

MeshMonitor's Node.js process typically uses 200–350 MB at runtime. With OS and Docker overhead the total is around 700–900 MB, leaving 3+ GB free on a 4 GB Pi. The free RAM is used by the OS as a file cache, which actually reduces SD reads.

| RAM | Verdict |
|---|---|
| 1 GB | ⚠️ Tight — may work but leaves little headroom |
| 2 GB | ✅ Comfortable for this single-container stack |
| 4 GB | ✅ Tested — plenty of headroom |
| 8 GB | ✅ No issues |

### Supported Boards

| Board | Architecture | Status |
|---|---|---|
| Pi 3B / 3B+ | armv7 (32-bit) | ⚠️ Untested — armv7 image exists; MeshMonitor dev runs this setup, but setup.sh targets 64-bit OS |
| Pi 4 (any RAM) | arm64 | ✅ Tested |
| Pi 5 | arm64 | ✅ Should work — same architecture, faster; no known issues |
| Pi Zero 2W | arm64 | ⚠️ Untested — 512 MB RAM is very tight |

If you run this on a Pi 3B+ or Pi 5, please open an issue and let us know how it goes.

### SD Card

SD card quality matters more than size for a 24/7 appliance. Cheap cards fail under continuous low-level writes even with our write minimization in place.

**Recommended (in order):**
- Samsung Endurance Pro — designed for dashcams and surveillance, highest write endurance
- SanDisk High Endurance — same use case, excellent choice
- Samsung Endurance (non-Pro) — good
- SanDisk Extreme — general purpose but solid

**Avoid:** SanDisk Ultra, Kingston, unbranded or Amazon Basics cards.

**Size:** 32 GB is the sweet spot. The full stack (OS + Docker + images + database) uses around 6 GB. 16 GB works but leaves less room for image churn during upgrades. Larger cards (64 GB+) offer no benefit and budget-tier large cards often have worse endurance than mid-size ones.

---

## SD Card Write Minimization

Five layers of protection keep writes off the SD card:

1. **Docker `local` log driver** — capped at 100KB × 2 files per container
2. **`daemon.json`** — system-wide Docker log cap as belt-and-suspenders
3. **`ACCESS_LOG_ENABLED=false`** — kills HTTP access logging in MeshMonitor
4. **tmpfs `/data/logs`** — MeshMonitor's audit log goes to RAM, never SD
5. **OS hardening via `setup.sh`** — `noatime`, volatile systemd journal, tmpfs `/var/log`

The only necessary SD writes are the SQLite database (`meshmonitor-data` Docker volume) and Docker image layers pulled during upgrades.

---

## Prerequisites

- Raspberry Pi running **Raspberry Pi OS Lite 64-bit** (bookworm)
- Network connectivity (Ethernet recommended for reliability)
- At least one Meshtastic node — connected via WiFi/Ethernet (TCP), Bluetooth (BLE), or USB cable (serial). TCP is the simplest option if your node is on the same network as the Pi.
- DHCP reservation configured in your router so the Pi always gets the same IP

---

## First-Time Setup

### 1. Reserve a static IP for the Pi

In your router's DHCP settings, find the Pi's MAC address and assign it a permanent IP reservation. The Pi itself uses normal DHCP — the reservation just ensures it always gets the same address. Note that IP — you'll need it when running `setup.sh`.

### 2. Clone this repo onto the Pi

```bash
git clone https://github.com/sfaith/meshmonitor-pi.git
cd meshmonitor-pi
```

### 3. Run setup

```bash
chmod +x setup.sh
./setup.sh
```

The script will walk you through confirming all settings, harden the OS, configure Docker, and start the stack.

`setup.sh` generates a session secret automatically on first run — no manual step needed. If you prefer to supply your own, generate one and add it to `.env` before running setup:

```bash
openssl rand -hex 32
```

Set `SESSION_SECRET=<output>` in `.env` — setup.sh will detect and keep it.

### 4. Reboot

```bash
sudo reboot
```

This applies the `/etc/fstab` changes (`noatime`, tmpfs `/var/log`).

### 5. Verify the stack came back up

```bash
cd meshmonitor-pi
docker compose ps
```

The container should show `running (healthy)`.

`setup.sh` is safe to re-run at any time — all steps check before acting and skip anything already configured.

### 6. Change the default password

Open `http://<PI_IP>:8080` in a browser, log in with `admin` / `changeme`, and immediately change the password via the top-right menu.

## Day-to-Day Operations

> **Note:** For most changes — adding nodes, updating settings — just re-run `./setup.sh`. The commands below are for day-to-day monitoring and maintenance.

```bash
# Live logs
docker compose logs -f

# Status
docker compose ps

# Stop stack
docker compose down

# Manual upgrade (cron handles this automatically at 3 AM)
./launch.sh pull && ./launch.sh up -d

# Restart a single service
docker compose restart meshmonitor
```

## Auto-Upgrade

A cron job installed by `setup.sh` runs `docker compose pull && docker compose up -d` daily at 3 AM (`America/Phoenix`). When a new image is available it pulls it and recreates the container, removing the old layer to reclaim SD space.

To change the schedule, edit `UPGRADE_TIME` in `.env` (24-hour `HH:MM` format) and re-run `setup.sh` to reinstall the cron job.

To check the upgrade log:
```bash
cat ~/meshmonitor-upgrade.log
```

## Adding a Serial Node

Re-run `./setup.sh` and choose **"Add a serial/USB node"** from the Node Connections menu. The wizard will detect your device, walk you through the configuration, and restart the stack automatically.

Before running setup, make sure serial mode is enabled on your Meshtastic device. From a computer connected to the device:

```bash
meshtastic --set serial.enabled true
meshtastic --set serial.mode SIMPLE
```

## MQTT Integration

MeshMonitor 4.0 supports MQTT natively — no sidecar container needed. To add an MQTT source:

**Dashboard → Sources → Add → MQTT**

Enter your broker address, credentials, and topic. For the Arizona regional mesh (`azmsh.net`):
```
Broker   : mqtt.azmsh.net
Topic    : msh/US/AZ/Tucson/#
Username : azmshpub
```
*These are credentials for the Arizona regional mesh. Check your regional mesh community for the correct broker and topic.*

## Troubleshooting

**Blank white screen in browser**
Check `ALLOWED_ORIGINS` in `.env` — it must exactly match the URL you're using to access the UI, including the port.

**MeshMonitor can't connect to the node**
```bash
ping YOUR_NODE_IP
nc -zv YOUR_NODE_IP 4403
```

**Reset MeshMonitor data**
```bash
docker compose down
docker volume rm meshmonitor-pi_meshmonitor-data
docker compose up -d
```

## Maintenance

Periodically check the [MeshMonitor CHANGELOG](https://github.com/Yeraze/meshmonitor/blob/main/CHANGELOG.md) for breaking changes that may affect this deployment — particularly env var renames or removals, new required variables, healthcheck endpoint changes, and Docker image tag changes. Our `ENABLE_VIRTUAL_NODE` removal in v0.1.4 is an example of the kind of upstream change to watch for.

## References

- [MeshMonitor Documentation](https://meshmonitor.org/)
- [MeshMonitor GitHub](https://github.com/yeraze/meshmonitor)
- [MeshMonitor Discord](https://discord.gg/JVR3VBETQE)
- [Meshtastic](https://meshtastic.org/)
