# meshmonitor-pi
![Version](https://img.shields.io/badge/version-0.3.8-blue) ![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-lightgrey) ![License](https://img.shields.io/badge/license-BSD--3--Clause-green)

Turn a spare Raspberry Pi into a self-maintaining [MeshMonitor](https://meshmonitor.org/) instance. Starting from a fresh Raspberry Pi OS Lite install, a single setup wizard handles Docker installation, node configuration, SD card write protection, systemd boot service, automatic daily upgrades with push failure alerts, and weekly maintenance — everything you'd otherwise piece together yourself.

---

## Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
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

1. Flash **Raspberry Pi OS Lite** (64-bit) via Raspberry Pi Imager with SSH and password authentication enabled
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
5. Reboot to apply SD card and storage optimizations:
   ```bash
   sudo reboot
   ```
6. Verify — meshmonitor should show healthy (may take a few minutes on first boot):
   ```bash
   ./launch.sh status
   ```
7. Open `http://<PI_IP>:8080`, change the default password (`admin` / `changeme`)

</details>

---

## Installation

> **New to Raspberry Pi?** You'll need to be comfortable with accessing your router's admin page and connecting to the Pi via SSH (Windows: [Windows Terminal](https://aka.ms/terminal) or [PuTTY](https://www.putty.org/) — Mac/Linux: Terminal). If any of that sounds unfamiliar, the [Raspberry Pi Getting Started guide](https://www.raspberrypi.com/documentation/computers/getting-started.html) is an excellent place to begin.

### What you need
- A Raspberry Pi — see [Hardware](#hardware) below for board and SD card recommendations
- A computer to write the SD card
- Your Pi connected to your router via Ethernet or WiFi
- At least one Meshtastic node — TCP is the simplest; BLE and serial also supported

---

### Hardware

#### Tested Configurations

| Component | Used |
|---|---|
| **Board** | Raspberry Pi 4 (4 GB RAM), Raspberry Pi 5 (8 GB RAM), Raspberry Pi 3B+ (1 GB RAM) |
| **SD card** | 32 GB Samsung Endurance Pro |
| **OS** | Raspberry Pi OS Lite 64-bit (Trixie) |

#### Supported Boards

| Board | Architecture | Status |
|---|---|---|
| Pi 3B / 3B+ | arm64 (64-bit) | ✅ Tested (Pi 3B+) — 1 GB RAM marginal; suitable for small meshes only |
| Pi 4 (any RAM) | arm64 | ✅ Tested (Pi 4 4GB) — 2 GB+ recommended for larger meshes |
| Pi 5 | arm64 | ✅ Tested (Pi 5 8GB) |
| Pi Zero 2W | arm64 | ⚠️ Untested — 512 MB RAM is very tight |

#### RAM

| RAM | Verdict |
|---|---|
| 512 MB | ❌ Not recommended |
| 1 GB | ⚠️ Marginal — small meshes only |
| 2 GB | ✅ Comfortable |
| 4 GB | ✅ Tested |
| 8 GB | ✅ No issues |

#### SD Card

Use an **endurance-rated** card designed for 24/7 write workloads — look for "High Endurance" or "Endurance Pro" in the product name. Standard cards, even name brands, are optimized for cameras and phones rather than long-term continuous operation. **Tested with:** Samsung Endurance Pro (recommended). 32 GB is the sweet spot — actual usage varies significantly with mesh size and data retention settings, but 32 GB provides comfortable headroom for virtually any deployment.

---

### Step-by-Step Installation

New to Raspberry Pi or just want the full walkthrough? The steps below cover everything from flashing the SD card to a running MeshMonitor instance.

---

### Phase 1 — Get the Pi ready

**1. Write the SD card**

Download and install the [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Open it and:

1. Click **Choose Device** → select your Pi model
2. Click **Choose OS** → **Raspberry Pi OS (other)** → **Raspberry Pi OS Lite**
   > Pi 3B/3B+ or newer: select the 64-bit image
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
cd ~
sudo apt install -y git curl openssl bluez
git clone https://github.com/sfaith/meshmonitor-pi.git && cd meshmonitor-pi
chmod +x setup.sh launch.sh scan-ble.sh
./setup.sh
```

> If the clone fails, common causes:
> - `Could not resolve host: github.com` — no internet connection. Check your network and try again.
> - `Permission denied (publickey)` — you're using SSH instead of HTTPS. The command above uses HTTPS and should not require a GitHub account.
> - `destination path already exists` — a previous clone attempt left a partial directory. Run `rm -rf meshmonitor-pi` and try again.

The wizard installs Docker, applies SD card and storage optimizations, configures your nodes, and starts the stack. By the time it completes, MeshMonitor is running.

**5. Reboot to apply SD card and storage optimizations**

```bash
sudo reboot
```

This applies `noatime`, tmpfs mounts, and journal configuration to minimize SD card writes. The stack restarts automatically — no manual action needed.

**6. Verify and open the web UI**

Open `http://<PI_IP>:8080` in your browser and log in with `admin` / `changeme`. **Change the password immediately.**

> The container may take a few minutes to report healthy on first boot — if the page doesn't load right away, wait a minute and try again. To check status from the command line:
> ```bash
> ./launch.sh status
> ```

---

## SD Card Write Minimization

SD cards wear out faster when written to constantly. This project applies five layers of protection to keep writes to a minimum: Docker log size caps, `ACCESS_LOG_ENABLED=false` to suppress HTTP access logging, a tmpfs (RAM disk) for MeshMonitor's own log files, and OS-level optimizations — `noatime` (stops recording file access timestamps), a volatile systemd journal (logs go to RAM instead of the card), and tmpfs for `/var/log`. All of this is applied automatically by `setup.sh`. The only writes that actually hit the card are the SQLite database and Docker image layers during upgrades.

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
cat ~/.meshmonitor-upgrade-result       # Check last auto-upgrade outcome
```

Auto-upgrade runs daily at 3 AM. To change the schedule, edit `UPGRADE_TIME` in `.env` and re-run `./setup.sh`. To customize further, edit the crontab directly:
```bash
crontab -e
```

### Upgrade Failure Alerts

Set `NTFY_TOPIC` in `.env` to receive a push notification if the nightly upgrade fails. Pick any unique string as your topic name (treat it like a password), install the [ntfy app](https://ntfy.sh) on your phone, and subscribe to your topic. No account required. If `NTFY_TOPIC` is unset, alerting is silently disabled.

Full setup instructions are in `env.example` alongside the `NTFY_TOPIC` entry.

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

> These commands require the [Meshtastic CLI](https://meshtastic.org/docs/software/python/cli/) installed on a separate computer. Alternatively, configure serial mode via the **Meshtastic app** on [Android](https://meshtastic.org/docs/software/android/) or [iOS](https://meshtastic.org/docs/software/apple/) under **Radio Configuration → Module Config → Serial**.

---

## MQTT Integration

**Dashboard → Sources → Add → MQTT**

For the official Meshtastic public broker:
```
Broker   : mqtt.meshtastic.org
Topic    : msh/US/2/e/LongFast/#   (firmware-dependent — verify in the docs before using)
Username : meshdev
Password : large4cats
```
> The exact topic structure depends on your firmware version and region. The [Meshtastic MQTT docs](https://meshtastic.org/docs/software/integrations/mqtt/) are the authoritative source.

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

**🔌 Serial source not connecting**

Check the bridge container logs first, using the correct container name for your serial node (`meshmonitor-serial-1`, `meshmonitor-serial-2`, etc. — run `docker ps` to confirm):
```bash
docker logs meshmonitor-serial-1
```
Common causes:
- Wrong device path — run `ls /dev/ttyACM* /dev/ttyUSB*` to find the correct device
- Serial mode not enabled on the device — see [Adding More Nodes](#adding-more-nodes) for the config commands
- Permission denied — the Docker bridge accesses the device via the `devices:` mapping in the compose file, so host group membership isn't required. If you're accessing the device directly outside Docker, add your user to the `dialout` group: `sudo usermod -aG dialout $USER` then reboot
- Device reboot on connect — normal; the bridge disables HUPCL automatically on startup

**📶 BLE source stuck on 'connecting'**

Your device likely requires Bluetooth pairing before it will exchange data with the bridge. This affects PIN/passkey-protected devices. Re-run `./setup.sh`, select your BLE node, and choose to pair when prompted.

If you need to pair manually, first confirm your BLE container name with `docker ps` (it will be `meshmonitor-ble-1`, `meshmonitor-ble-2`, etc. depending on how many BLE nodes you have), then:
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

**⬜ Blank white screen** — check `ALLOWED_ORIGINS` in `.env` matches your URL exactly including port. Edit with `nano .env` from the `meshmonitor-pi` directory.

**📡 Node not connecting**
```bash
ping YOUR_NODE_IP
nc -zv YOUR_NODE_IP 4403
```
> If `nc` is not available: `bash -c 'echo >/dev/tcp/YOUR_NODE_IP/4403' && echo "open" || echo "closed"`

If `ping` fails, the Pi can't reach the node at all — check that the node is powered on and connected to your network. If `ping` succeeds but the port check fails, the node is reachable but not accepting connections on port 4403 — verify the TCP server is enabled and the correct port is configured in your node's settings. Refer to your node's documentation for configuration details.

**🔄 UI broke after overnight upgrade** — check the logs first, then the upstream [CHANGELOG](https://github.com/Yeraze/meshmonitor/blob/main/CHANGELOG.md) for any breaking changes introduced by the new version:
```bash
cat ~/.meshmonitor-upgrade-result
docker logs meshmonitor
```
To disable auto-upgrade temporarily: edit the crontab with `crontab -e` and comment out the `meshmonitor-pi auto-upgrade` line. Re-run `./setup.sh` or edit the crontab again to restore.

**⚠️ Reset MeshMonitor data**

> ⚠️ **This is destructive and irreversible.** All node history, telemetry, messages, and configuration stored by MeshMonitor will be permanently deleted. The application will start fresh as if newly installed.

```bash
./launch.sh down
docker volume rm meshmonitor-pi_meshmonitor-data
./launch.sh up -d
```

---

## Maintenance

**Stay current** — check the [MeshMonitor CHANGELOG](https://github.com/Yeraze/meshmonitor/blob/main/CHANGELOG.md) periodically — env var changes or new required variables can occasionally require a config update.

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
- [Meshtastic MQTT Documentation](https://meshtastic.org/docs/software/integrations/mqtt/)
