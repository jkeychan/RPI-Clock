# Meshtastic GPS Integration

GPS forwarding for RAK11300 Meshtastic module using software serial via GPIO.

## Hardware Setup

- **RAK RX0** → **Pi Pin 11 (GPIO 17)** - RAK receives GPS data from Pi
- **RAK TX0** → **Pi Pin 36 (GPIO 16)** - RAK sends data to Pi
- **GPS HAT** → Connected to Pi via UART0 (GPIO 14/15)

## Configuration

### Meshtastic GPS Settings

```bash
source meshtastic/bin/activate
meshtastic --port /dev/ttyACM0 --set position.rx_gpio 17
meshtastic --port /dev/ttyACM0 --set position.gps_enabled true
```

### Install Service

```bash
sudo cp gps-forward-gpio-direct.py /opt/rpi-clock/
sudo cp meshtastic-gps-forwarder.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable meshtastic-gps-forwarder.service
sudo systemctl start meshtastic-gps-forwarder.service
```

## How It Works

1. GPS HAT sends NMEA sentences to Pi via UART0
2. `gpspipe` reads NMEA sentences from GPS HAT via gpsd
3. GPS forwarder uses software serial (bit-banging) to write NMEA data to GPIO 17
4. RAK11300 reads GPS data from GPIO 17 (connected to RAK RX0)
5. Meshtastic processes GPS data and updates position

## Notes

- Raspberry Pi Zero 2 W only has one hardware UART, so software serial is used
- Requires RPi.GPIO library (`python3-rpi.gpio`)
- GPS forwarder runs as a systemd service and starts automatically on boot

