# RPI-Clock

![Vector logo of a Raspberry made to look like it has a digital display and futuristic](rpi-clock-logo.png)

A Raspberry Pi-based clock with GPS time synchronization and weather display using a 7-segment LED display. This project combines accurate GPS timekeeping with local weather information for a comprehensive desktop clock solution.

![Animated GIF of a 7-segment display cycling through displaying time, followed by outside temperature, heat index, and relative humidity values](rpi-clock.gif)

## Features

- **GPS Time Synchronization**: Uses Adafruit Ultimate GPS HAT for precise timekeeping
- **Weather Display**: Shows current temperature, feels-like temperature, and humidity
- **7-Segment Display**: Clean, readable LED display with scrolling text
- **Configurable**: Customizable time format, temperature units, and display cycles
- **Modular Design**: Easy to assemble and modify with plug-and-play connections

## Hardware Requirements

### Required Components

- **Raspberry Pi Zero 2 W** (or any Raspberry Pi with 40-pin GPIO header)
- **Adafruit Ultimate GPS HAT for Raspberry Pi** - Mini Kit
- **Adafruit 1.2" 4-Digit 7-Segment Display w/I2C Backpack** - Yellow
- **GPIO Stacking Header for Pi A+/B+/Pi 2/Pi 3** - Extra-long 2x20 Pins
- **CR1220 Coin Cell Battery** (for GPS HAT RTC backup)
- **JST 2.0mm 4-Pin Connector Set** - 10pcs with Mini Female and Male Plugs
- **Female-to-Female Dupont Jumper Wires** (4 wires minimum)
- **Dupont Crimping Tool** (for professional connections)
- **SMA to uFL/u.FL/IPX/IPEX RF Adapter Cable** (optional, for external antenna)
- **External GPS Antenna with SMA connector** (optional, improves indoor reception)

### Optional Components

- **Micro-USB OTG Adapter** (for future Meshtastic integration)
- **Project Enclosure** (for permanent installation)
- **Heat Shrink Tubing** (for cable management)

## Quick Start

1. **Assemble Hardware**: Follow the [Hardware Setup Guide](#hardware-setup) below
2. **Configure Raspberry Pi**: Complete the [System Configuration](#system-configuration) steps
3. **Install Dependencies**: Run the [Software Installation](#software-installation) commands
4. **Configure GPS Time Sync**: Set up [GPS Time Synchronization](#gps-time-synchronization)
5. **Update Configuration**: Edit `config.ini` with your settings
6. **Run the Clock**: Execute `python3 clock.py`

## Hardware Setup

### Step 1: GPS HAT Assembly

1. **Solder Stacking Header**: Instead of the standard header, solder the **extra-long stacking header** to the GPS HAT
2. **Insert Battery**: Place the CR1220 coin cell battery in the GPS HAT's battery holder
3. **Stack HAT**: Connect the GPS HAT to your Raspberry Pi's GPIO header

### Step 2: Display Connection

1. **Add Pins to Display**: Solder the 5 pin headers that came with the display to the back with the longer ends pointing towards the back.

2. **Connect Female Dupont Connectors to Display**: Connect the female Dupont wires to the 7-segment display backpack:
   - **Red** → **VCC** (+)
   - **Black** → **GND** (-)
   - **Yellow** → **SDA** (D)
   - **White** → **SCL** (C)

3. **Connect to Pi**: Plug the Dupont connectors to the stacking header pins:
   - **VCC** → **Pi 5V** pin 2
   - **GND** → **Pi GND** pin 6
   - **SDA** → **Pi SDA** (GPIO 2) pin 3
   - **SCL** → **Pi SCL** (GPIO 3) pin 5

### Step 3: Optional External Antenna

1. Connect the SMA to uFL adapter cable to the GPS HAT
2. Attach an external GPS antenna with SMA connector
3. Position antenna for optimal satellite reception

## System Configuration

### Enable Required Interfaces

1. **Open Raspberry Pi Configuration**:
   ```bash
   sudo raspi-config
   ```

2. **Enable I2C** (for display):
   - Navigate to `Interface Options` > `I2C`
   - Select `Yes` to enable I2C

3. **Configure Serial Port** (for GPS):
   - Navigate to `Interface Options` > `Serial Port`
   - Select `No` for login shell over serial
   - Select `Yes` to enable serial port hardware

4. **Reboot**:
   ```bash
   sudo reboot
   ```

### Disable Bluetooth (Pi Zero 2 W)

If using Raspberry Pi Zero 2 W, disable Bluetooth to free up UART:

1. **Add to `/boot/config.txt`**:
   ```bash
   sudo nano /boot/config.txt
   ```
   Add this line:
   ```
   dtoverlay=pi3-disable-bt
   ```

2. **Disable Bluetooth Service**:
   ```bash
   sudo systemctl disable hciuart
   ```

3. **Reboot**:
   ```bash
   sudo reboot
   ```

## Software Installation

### Install Python Dependencies

```bash
# Update package list
sudo apt update

# Install Python packages
pip3 install adafruit-circuitpython-ht16k33 requests configparser ntplib

# Install GPS daemon and clients
sudo apt install gpsd gpsd-clients

# Install time synchronization software
sudo apt install chrony
```

### Configure GPS Daemon (gpsd)

1. **Disable Default Service**:
   ```bash
   sudo systemctl stop gpsd.socket
   sudo systemctl disable gpsd.socket
   ```

2. **Start gpsd Manually**:
   ```bash
   sudo gpsd /dev/serial0 -F /var/run/gpsd.sock
   ```

3. **Test GPS Connection**:
   ```bash
   cgps -s
   ```
   Look for "3D fix" status indicating successful GPS lock.

## GPS Time Synchronization

### Option 1: Chrony (Recommended)

Chrony provides faster synchronization and better performance:

1. **Configure Chrony**:
   ```bash
   sudo nano /etc/chrony/chrony.conf
   ```

2. **Add GPS Reference**:
   Add these lines at the end of the file:
   ```
   # GPS reference clock
   refclock SHM 0 offset 0.5 delay 0.2 refid NMEA
   ```

3. **Restart Chrony**:
   ```bash
   sudo systemctl restart chrony
   ```

4. **Verify Synchronization**:
   ```bash
   chronyc sources
   ```
   Look for GPS source marked with asterisk (*).

### Option 2: Traditional NTP

If you prefer traditional NTP:

1. **Install NTP**:
   ```bash
   sudo apt install ntp
   ```

2. **Configure NTP**:
   ```bash
   sudo nano /etc/ntp.conf
   ```

3. **Add GPS Reference**:
   Add these lines:
   ```
   # GPS reference clock
   server 127.127.28.0 minpoll 4 maxpoll 4
   fudge 127.127.28.0 time1 0.420 refid GPS
   ```

4. **Restart NTP**:
   ```bash
   sudo systemctl restart ntp
   ```

## Configuration

### Update config.ini

Edit the `config.ini` file with your settings:

```ini
[Weather]
api_key = your_openweathermap_api_key_here
zip_code = your_zip_code_here

[Display]
time_format = 24
temp_unit = F

[NTP]
preferred_server = 127.0.0.1

[Cycle]
time_display = 2
temp_display = 2
feels_like_display = 2
humidity_display = 2
```

### Configuration Options

- **time_format**: `12` for 12-hour format, `24` for 24-hour format
- **temp_unit**: `C` for Celsius, `F` for Fahrenheit
- **preferred_server**: `127.0.0.1` for local GPS time, or external NTP server
- **Cycle settings**: Display duration in seconds for each metric

## Running the Clock

### Start the Clock

```bash
python3 clock.py
```

### Auto-Start on Boot

The setup script automatically creates a systemd service for auto-start. The clock files are installed to `/opt/rpi-clock/` and the service runs as your user.

**Manual Service Management**:
```bash
# Start the service
sudo systemctl start rpi-clock.service

# Stop the service
sudo systemctl stop rpi-clock.service

# Check service status
sudo systemctl status rpi-clock.service

# View service logs
sudo journalctl -u rpi-clock.service -f
```

**Configuration Updates**:
After installation, edit the configuration file:
```bash
sudo nano /opt/rpi-clock/config.ini
sudo systemctl restart rpi-clock.service
```

## Troubleshooting

### GPS Issues

- **No GPS Fix**: Ensure antenna has clear view of sky
- **Slow Fix**: Wait 5-10 minutes for cold start
- **Poor Signal**: Use external antenna for indoor use

### Display Issues

- **No Display**: Check I2C connections and enable I2C interface
- **Wrong Characters**: Verify SDA/SCL connections
- **Dim Display**: Check power connections

### Time Sync Issues

- **Wrong Time**: Verify GPS fix and chrony/ntp status
- **Drift**: Check GPS antenna placement
- **No Sync**: Restart gpsd and chrony services

### Weather Issues

- **No Weather**: Check internet connection and API key
- **Wrong Location**: Verify ZIP code in config.ini

## Uninstalling

### Quick Uninstall

Use the provided uninstall script:
```bash
./uninstall.sh
```

### Manual Uninstall

To remove the RPI-Clock installation manually:

```bash
# Stop and disable the service
sudo systemctl stop rpi-clock.service
sudo systemctl disable rpi-clock.service

# Remove the service file
sudo rm /etc/systemd/system/rpi-clock.service

# Remove installed files
sudo rm -rf /opt/rpi-clock

# Reload systemd
sudo systemctl daemon-reload

# Optional: Remove dependencies (be careful if other projects use them)
# sudo apt remove gpsd gpsd-clients chrony
# pip3 uninstall adafruit-circuitpython-ht16k33 requests configparser ntplib
```

## Future Enhancements

- **Meshtastic Integration**: Add LoRa mesh networking capabilities
- **Multiple Displays**: Support for additional 7-segment displays
- **Web Interface**: Remote configuration and monitoring
- **Data Logging**: Historical weather and time data

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.






