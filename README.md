# meshmonitor-pi
![Version](https://img.shields.io/badge/version-0.3.6-blue) ![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-lightgrey) ![License](https://img.shields.io/badge/license-BSD--3--Clause-green)

A Docker deployment of [MeshMonitor](https://meshmonitor.org/) for Raspberry Pi — optimized for SD card longevity and hands-off operation.

---

## Contents

- [Quick Start](#quick-start)
- [Hardware](#hardware)
- [SD Card Write Minimization](#sd-card-write-minimization)
- [Day-to-Day Operations](#day-to-day-operations)
- [Adding More Nodes](#adding-more-nodes)
- [MQTT Integration](#mqtt-integration)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [References](#references)

---

## Quick Start

<details>
<summary>⚡ Quick install — expand if you know your way around a Pi</summary>

1. Flash **Raspberry Pi OS Lite** (64-bit for Pi 4/5, 32-bit for Pi 3B/3B+) via Raspberry Pi Imager with SSH and password authentication enabled
2. Reserve a static DHCP IP for your Pi in your router
3. SSH in, update OS and reboot:
   ```bash
   sudo apt update && sudo apt full-upgrade -y && sudo reboot
   ```
4. SSH back in, install dependencies and run setup:
   ```bash
   sudo apt install -y git curl openssl bluez && \
   git clone https://github.com/sfaith/meshmonitor-pi.git && \
   cd meshmonitor-pi && chmod +x setup.sh launch.sh scan-ble.sh && \
   ./setup.sh
   ```
   > If Docker wasn't pre-installed, setup.sh will install it and relaunch itself automatically. Just follow the prompts — it picks up where it left off.
5. Reboot to apply SD card optimizations:
   ```bash
   sudo reboot
   ```
6. Verify: `docker ps` — meshmonitor should show healthy (may take a few minutes on first boot)
7. Open `http://<PI_IP>:8080`, change the default password (`admin` / `changeme`)

</details>

---

> **New to Raspberry Pi?** You'll need to be comfortable with accessing your router's admin page and connecting to the Pi via SSH (Windows: [Windows Terminal](https://aka.ms/terminal) or [PuTTY](https://www.putty.org/) — Mac/Linux: Terminal). If any of that sounds unfamiliar, the [Raspberry Pi Getting Started guide](https://www.raspberrypi.com/documentation/computers/getting-started.html) is an excellent place to begin.

### What you need
- A Raspberry Pi — see [Hardware](#hardware) for board and SD card recommendations
- A computer to write the SD card
- Your Pi connected to your router via Ethernet or WiFi
- At least one Meshtastic node — TCP is the simplest; BLE and serial also supported

---

### Phase 1 — Get the Pi ready

**1. Write the SD card**

Download and install the [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Open it and:

1. Click **Choose Device** → select your Pi model
2. Click **Choose OS** → **Raspberry Pi OS (other)** → **Raspberry Pi OS Lite**
   - Pi 4 or 5: **64-bit** — Pi 3B/3B+: **32-bit**
3. Click **Choose Storage** → select your SD card
4. Click **Next** → **Edit Settings**:
   - Set a hostname (e.g. `meshmonitor`), username, and password
   - Configure WiFi if not using Ethernet
   - On the **Services** tab: **Enable SSH** → **Use password authentication**
   - Advanced users may prefer key-based authentication — the wizard supports either
5. Click **Save** → **Yes** → **Yes** to write

**2. Boot, find IP, and reserve it**

Insert the SD card and power on. After about a minute, find the Pi's IP in your router's connected devices list. While you're there, assign it a **permanent DHCP reservation** so it always gets the same address.

**3. SSH in and update the OS**

```bash
ssh yourusername@192.168.1.X
sudo apt update && sudo apt full-upgrade -y && sudo reboot
```

Wait for the Pi to reboot, then SSH back in. This ensures all OS updates are applied before installing anything.

---

### Phase 2 — Install MeshMonitor

**4. Install dependencies and run setup**

```bash
sudo apt install -y git curl openssl bluez
git clone https://github.com/sfaith/meshmonitor-pi.git
cd meshmonitor-pi && chmod +x setup.sh launch.sh scan-ble.sh
./setup.sh
```

The wizard hardens the OS, installs Docker, configures your nodes, and starts the stack. By the time it completes, MeshMonitor is running.

**5. Reboot to apply OS hardening**

```bash
sudo reboot
```

This applies the SD card optimizations (`noatime`, tmpfs `/var/log`) configured during setup. The stack restarts automatically — no manual action needed.

**6. Verify and open the web UI**

```bash
docker ps   # meshmonitor should show healthy
```

> The container may take a few minutes to start and report healthy — this is normal on first boot or after an upgrade.

Open `http://<PI_IP>:8080`, log in with `admin` / `changeme`, and **change the password immediately**.

> `setup.sh` is safe to re-run at any time. To supply your own session secret, run `openssl rand -hex 32`, set `SESSION_SECRET=<output>` in `.env`, then run setup.

---

## Hardware

### Tested Configuration

| Component | Used |
|---|---|
| **Board** | Raspberry Pi 4 (4 GB RAM) |
| **SD card** | 32 GB Samsung Endurance Pro |
| **OS** | Raspberry Pi OS Lite 64-bit (trixie) |

### Supported Boards

| Board | Architecture | Status |
|---|---|---|
| Pi 3B / 3B+ | armv7 (32-bit) | ⚠️ Untested — armv7 image exists; MeshMonitor dev runs this setup |
| Pi 4 (any RAM) | arm64 | ✅ Tested |
| Pi 5 | arm64 | ✅ Should work — same architecture, faster |
| Pi Zero 2W | arm64 | ⚠️ Untested — 512 MB RAM is very tight |

### RAM

| RAM | Verdict |
|---|---|
| 1 GB | ⚠️ Tight |
| 2 GB | ✅ Comfortable |
| 4 GB | ✅ Tested |
| 8 GB | ✅ No issues |

### SD Card

Use an endurance-rated card — cheap cards fail under 24/7 low-level writes. **Recommended:** Samsung Endurance Pro, SanDisk High Endurance. **Avoid:** SanDisk Ultra, Kingston, unbranded. 32 GB is the sweet spot — the full stack uses around 6 GB.

---

## SD Card Write Minimization

Five layers keep writes off the card: Docker log caps, `ACCESS_LOG_ENABLED=false`, tmpfs for MeshMonitor logs, and OS hardening (`noatime`, volatile journal, tmpfs `/var/log`) — all applied automatically by `setup.sh`. The only necessary writes are the SQLite database and Docker image layers during upgrades.

---

## Day-to-Day Operations

> For most changes — adding nodes, updating settings — just re-run `./setup.sh`.

```bash
docker logs -f meshmonitor              # Live logs
docker ps                               # Status (all containers)
./launch.sh status                      # Health, last upgrade, disk, uptime
./launch.sh up -d                       # Start stack
./launch.sh down                        # Stop stack
./launch.sh pull && ./launch.sh up -d  # Manual upgrade
./launch.sh down && ./launch.sh up -d  # Restart stack
./launch.sh prune                       # Remove unused Docker images and containers
cat ~/meshmonitor-upgrade.log           # Check last auto-upgrade or prune
```

Auto-upgrade runs daily at 3 AM. To change the schedule, edit `UPGRADE_TIME` in `.env` and re-run `./setup.sh`.

### Upgrade Failure Alerts

Set `NTFY_TOPIC` in `.env` to receive a push notification if the nightly upgrade fails. Pick any unique string as your topic name (treat it like a password), install the [ntfy app](https://ntfy.sh) on your phone, and subscribe to your topic. No account required. If `NTFY_TOPIC` is unset, alerting is silently disabled.

The last upgrade outcome is always visible in `./launch.sh status` regardless of alert configuration.

---

## Adding More Nodes

Re-run `./setup.sh` and choose the appropriate option from the Node Connections menu.

**BLE node:** Device must be powered on, within ~10 meters, and not connected to another app.

**Serial node:** Enable serial mode on the device first:
```bash
meshtastic --set serial.enabled true
meshtastic --set serial.echo false
meshtastic --set serial.mode SIMPLE
meshtastic --set serial.baud BAUD_115200
```

---

## MQTT Integration

**Dashboard → Sources → Add → MQTT**

For the official Meshtastic public broker:
```
Broker   : mqtt.meshtastic.org
Topic    : msh/US/2/e/LongFast/#   (adjust region — see docs)
Username : meshdev
Password : large4cats
```

For regional brokers, check your local mesh community. Example (Arizona mesh):
```
Broker   : mqtt.azmsh.net
Topic    : msh/US/AZ/Tucson/#
Username : azmshpub
Password : (find in the AZ Mesh Discord — https://azmsh.net/)
```

See the [Meshtastic MQTT docs](https://meshtastic.org/docs/software/integrations/mqtt/) for full topic structure and regional guidance. Regional brokers are coordinated via local mesh communities — check the [Meshtastic Discord](https://discord.com/invite/ktMAKGBnBs) for your region.

---

## Troubleshooting

**Serial source not connecting**

Check the bridge container logs first:
```bash
docker logs meshmonitor-serial-1
```
Common causes:
- Wrong device path — run `ls /dev/ttyACM* /dev/ttyUSB*` to find the correct device
- Serial mode not enabled on the device — see [Adding More Nodes](#adding-more-nodes) for the config commands
- Permission denied — add your user to the `dialout` group: `sudo usermod -aG dialout $USER` then reboot
- Device reboot on connect — normal; the bridge disables HUPCL automatically on startup

**BLE source stuck on 'connecting'**

Your device likely requires Bluetooth pairing before it will exchange data with the bridge. This affects PIN/passkey-protected devices. Re-run `./setup.sh`, select your BLE node, and choose to pair when prompted.

If you need to pair manually:
```bash
docker stop meshmonitor-ble-1
bluetoothctl
scan on
pair <YOUR_DEVICE_MAC>
trust <YOUR_DEVICE_MAC>
exit
docker start meshmonitor-ble-1
```
Power cycle the device first if pairing is rejected.

**Blank white screen** — check `ALLOWED_ORIGINS` in `.env` matches your URL exactly including port.

**Node not connecting**
```bash
ping YOUR_NODE_IP
nc -zv YOUR_NODE_IP 4403
```

**UI broke after overnight upgrade** — check the log, then the upstream CHANGELOG:
```bash
cat ~/meshmonitor-upgrade.log
docker logs meshmonitor
```
To disable auto-upgrade temporarily: `crontab -e` and comment out the `meshmonitor-pi auto-upgrade` line. Re-run `./setup.sh` to restore.

**Reset MeshMonitor data**
```bash
./launch.sh down
docker volume rm meshmonitor-pi_meshmonitor-data
./launch.sh up -d
```

---

## Maintenance

Check the [MeshMonitor CHANGELOG](https://github.com/Yeraze/meshmonitor/blob/main/CHANGELOG.md) periodically — env var changes or new required variables can occasionally require a config update.

**Disk space** — Docker accumulates stale image layers over time from daily auto-upgrades. A weekly prune cron is installed automatically by `setup.sh`. To reclaim space manually:
```bash
./launch.sh prune
```

**Health check** — a quick way to verify everything is running correctly after a period away:
```bash
./launch.sh status
```

This shows container health, MeshMonitor version, last upgrade outcome, NTFY alert status, disk usage, and uptime in one view.

---

## References

- [MeshMonitor Documentation](https://meshmonitor.org/)
- [MeshMonitor GitHub](https://github.com/yeraze/meshmonitor)
- [MeshMonitor Discord](https://discord.gg/JVR3VBETQE)
- [Meshtastic](https://meshtastic.org/)
