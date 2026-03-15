# Meshtastic GPS Integration

GPS position injection for a RAK11310 Meshtastic module using the Meshtastic Python API over USB.

## Hardware

- **RAK11310** connected via USB to the Pi (`/dev/ttyACM0`)
- **Adafruit Ultimate GPS HAT** providing position via gpsd

No GPIO wiring between the Pi and the RAK board is needed. The Pi injects position over the USB serial connection using the Meshtastic Python API.

## How It Works

1. `gpsd` reads NMEA sentences from the GPS HAT (`/dev/ttyAMA0`)
2. `gps-meshtastic-inject.py` reads TPV (time-position-velocity) fixes from gpsd via `gpspipe`
3. When a valid 2D or 3D fix is available, the script calls `localNode.setFixedPosition()` on the RAK11310 every 2 minutes
4. The RAK11310 broadcasts the injected position over the LoRa mesh

This replaces the unreliable GPIO bit-bang software-serial approach used in earlier versions.

## Installation

The `setup.sh` script handles this automatically. For manual setup:

```bash
# Create Python virtual environment
sudo python3 -m venv /opt/rpi-clock/venv

# Install Meshtastic library
sudo /opt/rpi-clock/venv/bin/pip install meshtastic

# Copy the inject script
sudo cp gps-meshtastic-inject.py /opt/rpi-clock/

# Install and enable the systemd service
sudo cp meshtastic-gps-forwarder.service /etc/systemd/system/
# Edit User= to match your username
sudo nano /etc/systemd/system/meshtastic-gps-forwarder.service
sudo systemctl daemon-reload
sudo systemctl enable --now meshtastic-gps-forwarder.service
```

## Meshtastic Node Configuration

Recommended settings for a stationary node (apply via the Meshtastic app or CLI):

```yaml
position:
  positionBroadcastSmartEnabled: false  # disable smart broadcast (we inject manually)
  gpsMode: NOT_PRESENT                  # tell radio GPS is handled externally
bluetooth:
  enabled: false                        # disable BLE (not needed when using USB)
power:
  lsSecs: 0                             # disable light sleep (stay always on)
```

## Checking Status

```bash
# View recent position injections
sudo journalctl -u meshtastic-gps-forwarder -n 30

# List visible mesh nodes (stop service first to free the port)
sudo systemctl stop meshtastic-gps-forwarder
/opt/rpi-clock/venv/bin/meshtastic --port /dev/ttyACM0 --nodes
sudo systemctl start meshtastic-gps-forwarder
```

## Graceful Shutdown

Always stop the forwarder before running the Meshtastic CLI — it holds `/dev/ttyACM0` exclusively:

```bash
sudo systemctl stop meshtastic-gps-forwarder
# ... run CLI commands ...
sudo systemctl start meshtastic-gps-forwarder
```
