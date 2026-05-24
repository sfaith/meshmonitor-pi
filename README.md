# meshmonitor-pi
![Version](https://img.shields.io/badge/version-0.3.3-blue) ![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-lightgrey) ![License](https://img.shields.io/badge/license-BSD--3--Clause-green)

A Docker deployment of [MeshMonitor](https://meshmonitor.org/) for Raspberry Pi — optimized for SD card longevity and hands-off operation.

## Quick Start

<details>
<summary>Already know what you're doing? Click here for the short version.</summary>

1. Flash **Raspberry Pi OS Lite** (64-bit for Pi 4/5, 32-bit for Pi 3B/3B+) via Raspberry Pi Imager with SSH and password authentication enabled
2. Reserve a static DHCP IP for your Pi in your router
3. SSH in and run:
   ```bash
   sudo apt update && sudo apt full-upgrade -y && \
   sudo apt install -y git curl openssl bluez && \
   git clone https://github.com/sfaith/meshmonitor-pi.git && \
   cd meshmonitor-pi && chmod +x setup.sh launch.sh scan-ble.sh && \
   ./setup.sh
   ```
4. When setup completes, reboot to apply SD card optimizations:
   ```bash
   sudo reboot
   ```
5. Verify the stack came back up: `docker ps` — both `meshmonitor` and any bridge containers should show running
6. Open `http://<PI_IP>:8080`, change the default password (`admin` / `changeme`)

</details>

---

> **New to Raspberry Pi?** You'll need to be comfortable with:
> - Accessing your router's admin page to find your Pi's IP address
> - Using a terminal application to connect to your Pi via SSH
>   (Windows: [Windows Terminal](https://aka.ms/terminal) or [PuTTY](https://www.putty.org/) — Mac/Linux: Terminal)
>
> If any of that sounds unfamiliar, the [Raspberry Pi Getting Started guide](https://www.raspberrypi.com/documentation/computers/getting-started.html) is an excellent place to begin.

### What you need
- A Raspberry Pi — see the [Hardware](#hardware) section for board and SD card recommendations
- A computer to write the SD card
- Your Pi connected to your router via Ethernet or WiFi

### 1. Write the SD card
Download and install the [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on your computer. Open it and:

1. Click **Choose Device** and select your Pi model
2. Click **Choose OS** → **Raspberry Pi OS (other)** → **Raspberry Pi OS Lite**
   - Pi 4 or 5: choose the **64-bit** version
   - Pi 3B / 3B+: choose the **32-bit** version
3. Click **Choose Storage** and select your SD card
4. Click **Next** — when asked about OS customization settings, click **Edit Settings**:
   - Set a hostname (e.g. `meshmonitor`)
   - Set a username and password — you'll use these to log in via SSH
   - Configure WiFi credentials if not using Ethernet
   - On the **Services** tab, check **Enable SSH** and select **Use password authentication**
   - Advanced users may prefer key-based authentication — the wizard supports either
5. Click **Save** → **Yes** → **Yes** to write the card

### 2. Boot the Pi and find its IP
Insert the SD card, connect Ethernet if using it, and power on. After about a minute find the Pi's IP address in your router's connected devices list.

While you're in your router, assign the Pi a **permanent DHCP reservation** — this makes sure your Pi always gets the same address on your network so you can always find it. Note the IP address down.

### 3. SSH into the Pi
Open a terminal on your computer and connect to the Pi:
- **Windows:** open Windows Terminal or PuTTY and connect to your Pi's IP address
- **Mac / Linux:** open Terminal

```bash
ssh yourusername@192.168.1.X
```
Replace `yourusername` with the username you set in the Imager, and `192.168.1.X` with your Pi's IP address.

### 4. Run the bootstrap command
Paste this full block into the terminal — it updates the OS, installs dependencies, clones the repo, and launches the setup wizard automatically:

```bash
sudo apt update && sudo apt full-upgrade -y && \
sudo apt install -y git curl openssl bluez && \
git clone https://github.com/sfaith/meshmonitor-pi.git && \
cd meshmonitor-pi && chmod +x setup.sh launch.sh scan-ble.sh && \
./setup.sh
```

> The OS upgrade may take a few minutes. The wizard will launch automatically when it's done. The stack will be running by the time the wizard completes.

### 5. Reboot
```bash
sudo reboot
```
This applies SD card optimizations (`noatime`, tmpfs `/var/log`) configured during setup. The stack starts automatically on reboot via systemd — no manual action needed.

### 6. Verify the stack came back up
```bash
docker ps
```
The `meshmonitor` container should show `healthy`. Any BLE or serial bridge containers will also appear here.

### 7. Open the web UI
Navigate to `http://<PI_IP>:8080` in your browser and log in with `admin` / `changeme`. **Change the password immediately** via the top-right menu.

See the sections below for hardware recommendations, adding nodes, and troubleshooting.

---

## What's Included

| Container | Purpose |
|---|---|
| `meshmonitor` | Web dashboard — connects to Meshtastic nodes via TCP, serial, or BLE |

MQTT integration is available natively in MeshMonitor 4.0 via Dashboard → Sources → Add → MQTT. No sidecar needed.

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

- Raspberry Pi running **Raspberry Pi OS Lite** (64-bit for Pi 4/5, 32-bit for Pi 3B/3B+)
- Network connectivity (Ethernet recommended for reliability)
- At least one Meshtastic node — connected via WiFi/Ethernet (TCP), Bluetooth (BLE), or USB cable (serial). TCP is the simplest option if your node is on the same network as the Pi.
- DHCP reservation configured in your router so the Pi always gets the same IP

---

## First-Time Setup

### 1. Reserve a static IP for the Pi

In your router's DHCP settings, find the Pi's MAC address and assign it a permanent IP reservation. The Pi itself uses normal DHCP — the reservation just ensures it always gets the same address. Note that IP — you'll need it when running `setup.sh`.

### 2. Install dependencies and clone this repo onto the Pi

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git curl openssl bluez
git clone https://github.com/sfaith/meshmonitor-pi.git
cd meshmonitor-pi
chmod +x setup.sh launch.sh scan-ble.sh
```

### 3. Run setup

```bash
./setup.sh
```

The wizard walks you through confirming all settings, hardens the OS, configures Docker, and starts the stack. By the time it completes, MeshMonitor is running.

`setup.sh` generates a session secret automatically on first run — no manual step needed. If you prefer to supply your own, generate one and add it to `.env` before running setup:

```bash
openssl rand -hex 32
```

Set `SESSION_SECRET=<output>` in `.env` — setup.sh will detect and keep it.

### 4. Reboot

```bash
sudo reboot
```

This applies the `/etc/fstab` changes (`noatime`, tmpfs `/var/log`) configured during setup. The stack restarts automatically via systemd — no manual action needed.

### 5. Verify the stack came back up

```bash
docker ps
```

The `meshmonitor` container should show `healthy`. Any BLE or serial bridge containers will also appear here.

`setup.sh` is safe to re-run at any time — all steps check before acting and skip anything already configured.

### 6. Change the default password

Open `http://<PI_IP>:8080` in a browser, log in with `admin` / `changeme`, and immediately change the password via the top-right menu.

## Day-to-Day Operations

> **Note:** For most changes — adding nodes, updating settings — just re-run `./setup.sh`. The commands below are for day-to-day monitoring and maintenance.

```bash
# Live logs (main container only)
docker logs -f meshmonitor

# Live logs (all containers including bridges)
docker ps --format '{{.Names}}' | xargs -I{} docker logs -f {}

# Status — all containers including bridges
docker ps

# Stop stack
./launch.sh down

# Manual upgrade (cron handles this automatically at 3 AM)
./launch.sh pull && ./launch.sh up -d

# Restart the stack (includes bridge containers)
./launch.sh down && ./launch.sh up -d
```

## Auto-Upgrade

The stack updates itself automatically every night at 3 AM — no action needed. When a new image is available it pulls it and restarts the containers.

To check the last upgrade:
```bash
cat ~/meshmonitor-upgrade.log
```

To change the schedule, edit `UPGRADE_TIME` in `.env` (24-hour `HH:MM` format) and re-run `./setup.sh` to reinstall the cron job.

To reclaim disk space from old image layers:
```bash
docker image prune -f
```

## Adding More Nodes

Re-run `./setup.sh` and choose the appropriate option from the Node Connections menu. The wizard will walk you through configuration and restart the stack automatically.

### BLE (Bluetooth) Node

Make sure your Meshtastic device is:
- Powered on and within ~10 meters of the Pi
- Not actively connected to another phone or app

### Serial (USB) Node

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
curl -v telnet://YOUR_NODE_IP:4403
```

**UI stopped working after an overnight upgrade**

Check the upgrade log first:
```bash
cat ~/meshmonitor-upgrade.log
```
Then check container status and logs:
```bash
docker ps
docker logs meshmonitor
```
Check the [MeshMonitor CHANGELOG](https://github.com/Yeraze/meshmonitor/blob/main/CHANGELOG.md) for breaking changes — env var renames or removals are the most common cause.

If the image itself is broken, disable auto-upgrade while you wait for an upstream fix:
```bash
crontab -e
```
Comment out the `meshmonitor-pi auto-upgrade` line. Re-run `./setup.sh` to restore it when ready. Note: MeshMonitor does not publish versioned image tags, so rolling back is not possible — waiting for an upstream fix is the fastest path.

**Reset MeshMonitor data**
```bash
./launch.sh down
docker volume rm meshmonitor-pi_meshmonitor-data
./launch.sh up -d
```

## Maintenance

Periodically check the [MeshMonitor CHANGELOG](https://github.com/Yeraze/meshmonitor/blob/main/CHANGELOG.md) for breaking changes that may affect this deployment — particularly env var renames or removals, new required variables, healthcheck endpoint changes, and Docker image tag changes. MeshMonitor moves quickly and upstream changes can occasionally require config updates.

## References

- [MeshMonitor Documentation](https://meshmonitor.org/)
- [MeshMonitor GitHub](https://github.com/yeraze/meshmonitor)
- [MeshMonitor Discord](https://discord.gg/JVR3VBETQE)
- [Meshtastic](https://meshtastic.org/)
