# meshmonitor-pi
![Version](https://img.shields.io/badge/version-0.1.2-blue)

Raspberry Pi 4 (arm64) Docker deployment of [MeshMonitor](https://meshmonitor.org/) — optimized for SD card longevity and hands-off operation.

## What's Included

| Container | Purpose |
|---|---|
| `meshmonitor` | Web dashboard — connects to Meshtastic node via TCP |
| `mqtt-proxy` | Bridges MeshMonitor's Virtual Node to upstream MQTT broker |
| `watchtower` | Pulls updated images nightly (3 AM), cleans up old layers |

Serial bridge is pre-stubbed in `docker-compose.yml` for future use — see [Adding a Serial Node](#adding-a-serial-node).

## SD Card Write Minimization

Five layers of protection keep writes off the SD card:

1. **Docker `local` log driver** — capped at 100KB × 2 files per container
2. **`daemon.json`** — system-wide Docker log cap as belt-and-suspenders
3. **`ACCESS_LOG_ENABLED=false`** — kills HTTP access logging in MeshMonitor
4. **tmpfs `/data/logs`** — MeshMonitor's audit log goes to RAM, never SD
5. **OS hardening via `setup.sh`** — `noatime`, volatile systemd journal, tmpfs `/var/log`

The only necessary SD writes are the SQLite database (`meshmonitor-data` Docker volume) and Docker image layers pulled during upgrades.

## Prerequisites

- Raspberry Pi 4 running **Raspberry Pi OS Lite 64-bit** (bookworm)
- Network connectivity (Ethernet recommended for reliability)
- Meshtastic node reachable on your LAN via TCP (port 4403)
- Static IP assigned to the Pi in your router's DHCP settings

## First-Time Setup

### 1. Assign a static IP to the Pi

In your router's admin interface, find the Pi's MAC address and assign it a permanent IP (DHCP reservation). Note that IP — you'll need it in the next step.

### 2. Clone this repo onto the Pi

```bash
git clone https://github.com/sfaith/meshmonitor-pi.git
cd meshmonitor-pi
```

### 3. Generate a session secret

```bash
openssl rand -hex 32
```

Copy the output — you'll paste it into `setup.sh` when prompted.

### 4. Run setup

```bash
chmod +x setup.sh
./setup.sh
```

The script will walk you through confirming all settings, harden the OS, configure Docker, and start the stack.

### 5. Reboot

```bash
sudo reboot
```

This applies the `/etc/fstab` changes (`noatime`, tmpfs `/var/log`).

### 6. Verify the stack came back up

```bash
cd meshmonitor-pi
docker compose ps
```

All containers should show `running (healthy)` or `running`.

### 7. Change the default password

Open `http://<PI_IP>:8080` in a browser, log in with `admin` / `changeme`, and immediately change the password via the top-right menu.

## Day-to-Day Operations

```bash
# Live logs
docker compose logs -f

# Status
docker compose ps

# Stop stack
docker compose down

# Manual upgrade (Watchtower handles this automatically)
docker compose pull && docker compose up -d

# Restart a single service
docker compose restart meshmonitor
```

## Watchtower (Auto-Upgrade)

Watchtower checks for new `meshmonitor` and `mqtt-proxy` images daily at 3 AM (`America/Phoenix`). When a new image is found it pulls it, recreates the container, and removes the old image layer to reclaim SD space.

To change the schedule, edit `WATCHTOWER_SCHEDULE` in `.env` (standard 6-field cron with seconds).

## Adding a Serial Node

When you're ready to attach a USB/serial Meshtastic node to the Pi:

1. Plug in the device and find its path:
   ```bash
   ls /dev/tty*   # usually /dev/ttyACM0 or /dev/ttyUSB0
   ```

2. Edit `.env` and set:
   ```
   SERIAL_DEVICE=/dev/ttyACM0
   MESHTASTIC_NODE_IP=serial-bridge
   ```

3. Edit `docker-compose.yml` and uncomment the `serial-bridge` service block.

4. Restart the stack:
   ```bash
   docker compose up -d
   ```

You can run both a TCP source and the serial bridge simultaneously — add the serial node as a second source from **Dashboard → Sources** in the MeshMonitor UI.

## MQTT Proxy

The `mqtt-proxy` container bridges MeshMonitor's Virtual Node (port 4404) to the upstream MQTT broker defined in `.env`. Defaults connect to the public Meshtastic network (`mqtt.meshtastic.org`).

To disable MQTT bridging, comment out the `mqtt-proxy` service in `docker-compose.yml`.

To change the region/channel, update `MQTT_TOPIC` in `.env`. Examples:
```
msh/US/2/e/LongFast/#    # US LongFast (default)
msh/EU/2/e/LongFast/#    # Europe LongFast
msh/US/2/e/MediumSlow/#  # US MediumSlow
```

## Troubleshooting

**Blank white screen in browser**
Check `ALLOWED_ORIGINS` in `.env` — it must exactly match the URL you're using to access the UI, including the port.

**MeshMonitor can't connect to the node**
```bash
ping 10.45.72.250
nc -zv 10.45.72.250 4403
```

**mqtt-proxy keeps restarting**
It waits for MeshMonitor's healthcheck (Virtual Node on port 4404). Give MeshMonitor 30–60 seconds to fully start after boot before worrying about mqtt-proxy.

**Reset MeshMonitor data**
```bash
docker compose down
docker volume rm meshmonitor-pi_meshmonitor-data
docker compose up -d
```

## References

- [MeshMonitor Documentation](https://meshmonitor.org/)
- [MeshMonitor GitHub](https://github.com/yeraze/meshmonitor)
- [MeshMonitor Discord](https://discord.gg/JVR3VBETQE)
- [Meshtastic](https://meshtastic.org/)
