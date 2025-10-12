# RPI-Clock

![Vector logo of a Raspberry made to look like it has a digital display and futuristic](rpi-clock-logo.png)

A Raspberry Pi-based clock with GPS time synchronization and weather display using a 7-segment LED display. This project combines accurate GPS timekeeping with local weather information for a comprehensive desktop clock solution.

![Animated GIF of a 7-segment display cycling through displaying time, followed by outside temperature, heat index, and relative humidity values](rpi-clock.gif)

## Features

- **GPS Time Synchronization**: Uses Adafruit Ultimate GPS HAT for precise timekeeping
- **Weather Display**: Shows current temperature, feels-like temperature, and humidity
- **7-Segment Display**: Clean, readable LED display with scrolling text
- **Custom Text Display**: Configurable custom messages that scroll across the display at set intervals
- **Configurable**: Customizable time format, temperature units, display cycles, and custom text
- **Modular Design**: Easy to assemble and modify with plug-and-play connections

## Hardware Requirements

### Required Components

- **Raspberry Pi Zero 2 W** (or any Raspberry Pi with 40-pin GPIO header)
- **Adafruit Ultimate GPS HAT for Raspberry Pi** - Mini Kit
- **Adafruit 1.2" 4-Digit 7-Segment Display w/I2C Backpack** - Yellow
- **GPIO Stacking Header for Pi A+/B+/Pi 2/Pi 3** - Extra-long 2x20 Pins
- **CR1220 Coin Cell Battery** (for GPS HAT RTC backup)
- **JST 2.0mm 4-Pin Connector Set** - 10pcs with Mini Female and Male Plugs
- **Female-to-Female Dupont Jumper Wires** (5 wires minimum: VIN, IO, GND, SDA, SCL)
- **Dupont Crimping Tool** (for professional connections)
- **SMA to uFL/u.FL/IPX/IPEX RF Adapter Cable** (optional, for external antenna)
- **External GPS Antenna with SMA connector** (optional, improves indoor reception)

### Optional Components

- **Micro-USB OTG Adapter** (for future Meshtastic integration)
- **Project Enclosure** (for permanent installation)
- **Heat Shrink Tubing** (for cable management)

## Quick Start

1. **Clone Repository**: 
   ```bash
   git clone https://github.com/jkeychan/rpi-clock.git
   cd rpi-clock
   ```

2. **Run Automated Setup**: 
   ```bash
   ./setup.sh
   ```

3. **Configure Settings**: Edit `config.ini` with your OpenWeatherMap API key and ZIP code:
   ```bash
   sudo nano /opt/rpi-clock/config.ini
   ```

4. **Reboot** (if prompted by setup script)

5. **Verify Installation**: Check GPS and display are working:
   ```bash
   # Test GPS connection
   cgps -s
   
   # Check chrony sources
   chronyc sources
   
   # Check clock service
   sudo systemctl status rpi-clock
   ```

## Manual Installation

If you prefer manual setup over the automated script:

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
   - **Red** → **VIN** (5V power)
   - **Orange** → **IO** (3.3V logic)
   - **Black** → **GND** (ground)
   - **Yellow** → **SDA** (data)
   - **White** → **SCL** (clock)

3. **Connect to Pi**: Plug the Dupont connectors to the stacking header pins:
   - **VIN** → **Pi 5V** pin 2
   - **IO** → **Pi 3.3V** pin 1
   - **GND** → **Pi GND** pin 6
   - **SDA** → **Pi SDA** (GPIO 2) pin 3
   - **SCL** → **Pi SCL** (GPIO 3) pin 5

### Step 3: Optional External Antenna

1. Connect the SMA to uFL adapter cable to the GPS HAT
2. Attach an external GPS antenna with SMA connector
3. Position antenna for optimal satellite reception

## System Configuration

### Enable Required Interfaces

#### Option 1: Automated Setup (Recommended)

Use these commands to automatically enable I2C and configure the GPS HAT:

```bash
# Enable I2C interface
sudo raspi-config nonint do_i2c 0

# Configure serial port (disable login shell, enable hardware)
sudo raspi-config nonint do_serial 1

# Enable UART for GPS HAT
sudo sed -i 's/enable_uart=0/enable_uart=1/' /boot/firmware/config.txt

# Disable Bluetooth to free UART for GPS HAT
sudo sed -i '/enable_uart=1/a dtoverlay=disable-bt' /boot/firmware/config.txt

# Install I2C tools
sudo apt install -y i2c-tools

# Add user to i2c group (no need to logout/login)
sudo usermod -a -G i2c $USER

# Reboot to apply changes
sudo reboot
```

#### Option 2: Manual Configuration

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

4. **Configure GPS HAT** (manual step):
   ```bash
   # Enable UART for GPS HAT
   sudo sed -i 's/enable_uart=0/enable_uart=1/' /boot/firmware/config.txt
   
   # Disable Bluetooth to free UART for GPS HAT
   sudo sed -i '/enable_uart=1/a dtoverlay=disable-bt' /boot/firmware/config.txt
   ```

5. **Reboot**:
   ```bash
   sudo reboot
   ```

#### Option 3: Direct File Editing

You can also manually edit the configuration files:

```bash
# Enable I2C by adding to /boot/firmware/config.txt
echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt

# Disable serial console login and enable hardware
sudo sed -i 's/console=serial0,115200//' /boot/firmware/cmdline.txt

# Enable UART for GPS HAT
echo "enable_uart=1" | sudo tee -a /boot/firmware/config.txt

# Disable Bluetooth to free UART for GPS HAT
echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt

# Install I2C tools and add user to group
sudo apt install -y i2c-tools
sudo usermod -a -G i2c $USER

# Reboot
sudo reboot
```

### Verify I2C Setup

After enabling I2C and rebooting, verify the setup is working:

1. **Check I2C Kernel Module**:
   ```bash
   lsmod | grep i2c
   ```
   You should see `i2c_dev` and `i2c_bcm2835` modules loaded.

2. **Install I2C Tools** (if not already installed):
   ```bash
   sudo apt install i2c-tools
   ```

3. **Detect I2C Devices**:
   ```bash
   sudo i2cdetect -y 1
   ```
   You should see a device at address `70` (the default address for the 7-segment display). If you see `UU` instead of `70`, the device is in use by another process.

4. **Check I2C Bus Status**:
   ```bash
   sudo i2cdetect -l
   ```
   Should show `i2c-1` bus available.

5. **Test Display Communication**:
   ```bash
   python3 -c "
   import board
   import busio
   i2c = busio.I2C(board.SCL, board.SDA)
   print('I2C devices found:', [hex(addr) for addr in i2c.scan()])
   "
   ```
   Should print `['0x70']` if the display is connected properly.

### Verify GPS HAT Setup

After enabling UART and disabling Bluetooth, verify the GPS HAT is detected:

1. **Check GPS HAT Device**:
   ```bash
   ls -la /dev/ttyAMA*
   ```
   You should see `/dev/ttyAMA0` if the GPS HAT is properly connected.

2. **Check I2C Detection**:
   ```bash
   sudo i2cdetect -y 1
   ```
   You should see a device at address `70` (GPS HAT I2C interface).

3. **Test GPS Connection**:
   ```bash
   # Install GPS tools
   sudo apt install gpsd gpsd-clients
   
   # Test GPS data reception with PPS auto-detection
   sudo gpsd -N -n /dev/ttyAMA0
   timeout 10 gpspipe -r | head -5
   ```
   Should show GPS data if antenna has clear sky view.
   PPS will be auto-detected if available for microsecond precision timing.

4. **Check GPS Status**:
   ```bash
   cgps -s
   ```
   Shows GPS fix status and satellite information.

### GPS HAT Configuration

The GPS HAT requires UART access and Bluetooth must be disabled to free the UART interface:

1. **UART and Bluetooth Configuration** (already configured in automated setup):
   ```bash
   # Enable UART for GPS HAT
   sudo sed -i 's/enable_uart=0/enable_uart=1/' /boot/firmware/config.txt
   
   # Disable Bluetooth to free UART for GPS HAT
   sudo sed -i '/enable_uart=1/a dtoverlay=disable-bt' /boot/firmware/config.txt
   ```

2. **Reboot**:
   ```bash
   sudo reboot
   ```

3. **Verify GPS HAT Detection**:
   ```bash
   # Check GPS HAT device
   ls -la /dev/ttyAMA*
   
   # Check PPS device (precision timing)
   ls -la /dev/pps*
   ```
   Should show `/dev/ttyAMA0` and `/dev/pps0` available for GPS HAT.
   PPS provides microsecond precision timing for chrony.

## Software Installation

### Install Python Dependencies

```bash
# Update package list
sudo apt update

# Install Python package manager
sudo apt install python3-pip

# Install required Python packages
pip3 install --break-system-packages adafruit-circuitpython-ht16k33 requests ntplib

# Install GPS daemon and clients
sudo apt install gpsd gpsd-clients

# Install time synchronization software
sudo apt install chrony
```

**Note**: On newer Debian/Ubuntu systems, you may encounter an "externally managed environment" error. The setup script handles this automatically with the `--break-system-packages` flag.

### Development Tools

The setup script also installs development tools for code quality:

```bash
# Install Python development tools
pip3 install --user flake8

# Install shellcheck for bash script validation
sudo apt install shellcheck
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

Chrony provides faster synchronization and better performance. The setup script automatically installs an optimized configuration that:

- Uses GPS as primary time source
- Serves time to all networks (public time server)
- Includes upstream NTP servers for backup
- Optimized for Raspberry Pi performance

**Manual Configuration** (if needed):
1. **Configure Chrony**:
   ```bash
   sudo nano /etc/chrony/chrony.conf
   ```

2. **Use Provided Configuration**:
   The setup script installs `chrony.conf` with optimized settings for GPS time serving.

3. **Restart Chrony**:
   ```bash
   sudo systemctl restart chrony
   ```

4. **Verify Synchronization**:
   ```bash
   chronyc sources
   ```
   Look for GPS source marked with asterisk (*).

**Public Time Server Features**:
- Serves time to all networks (`allow 0.0.0.0/0`)
- GPS + PPS reference clocks for maximum accuracy
- Upstream NTP servers for backup synchronization
- Optimized polling intervals for GPS sources

**Verify Public Time Serving**:
```bash
# Check chrony sources
chronyc sources

# Check chrony tracking
chronyc tracking

# Test from another machine
ntpdate -q your.pi.ip.address

# Check if port 123 is open
netstat -ulnp | grep :123
```

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

Edit the `config.ini` file with your settings. The application validates the configuration on startup and provides clear error messages for any issues:

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

[CustomText]
enabled = true
text = WART 95.5 FM
interval_minutes = 15
display_duration = 3
```

### Configuration Options

- **time_format**: `12` for 12-hour format, `24` for 24-hour format
- **temp_unit**: `C` for Celsius, `F` for Fahrenheit
- **smooth_scroll**: `true` for stock-ticker style scrolling (affects both weather and custom text), `false` for static display
- **preferred_server**: `127.0.0.1` for local GPS time, or external NTP server
- **Cycle settings**: Display duration in seconds for each metric (1-60 seconds)
- **CustomText settings**:
  - **enabled**: `true` to enable custom text display, `false` to disable
  - **text**: Custom message to display (max 50 characters recommended)
  - **interval_minutes**: How often to show custom text (1-1440 minutes, i.e., 1 minute to 24 hours)
  - **display_duration**: How long to display custom text (1-60 seconds)

### Configuration Validation

The application validates configuration on startup:
- Checks for required sections and options
- Validates API key format and ZIP code format
- Ensures display settings are valid
- Verifies cycle durations are within acceptable range
- Validates custom text settings when enabled
- Provides clear error messages for any issues

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

### Diagnostic Scripts

The project includes comprehensive diagnostic scripts to help troubleshoot issues:

```bash
# Test I2C display connection
./i2c-test.sh

# Test GPS connection and synchronization
./gps-test.sh

# Test NTP time synchronization
./ntp-test.sh
```

These scripts are installed to `/opt/rpi-clock/` and can be run from there.

### GPS Issues

- **No GPS Fix**: Ensure antenna has clear view of sky
- **Slow Fix**: Wait 5-10 minutes for cold start
- **Poor Signal**: Use external antenna for indoor use

### Display Issues

- **No Display**: Check I2C connections and enable I2C interface
- **Wrong Characters**: Verify SDA/SCL connections
- **Dim Display**: Check power connections

#### I2C Display Troubleshooting

If your display isn't working, follow these steps:

1. **Verify I2C is Enabled**:
   ```bash
   # Check if I2C modules are loaded
   lsmod | grep i2c
   
   # Check if I2C device exists
   ls /dev/i2c*
   ```

2. **Check Physical Connections**:
   - Ensure VIN (red) is connected to Pi pin 2 (5V)
   - Ensure IO (orange) is connected to Pi pin 1 (3.3V) - **REQUIRED**
   - Ensure GND (black) is connected to Pi pin 6 (GND)
   - Ensure SDA (yellow) is connected to Pi pin 3 (GPIO 2)
   - Ensure SCL (white) is connected to Pi pin 5 (GPIO 3)

3. **Test I2C Communication**:
   ```bash
   # Install i2c-tools if not already installed
   sudo apt install i2c-tools
   
   # Scan for I2C devices
   sudo i2cdetect -y 1
   ```
   Expected output should show `70` at the intersection of row 7, column 0.

4. **Check for Address Conflicts**:
   ```bash
   # If you see UU instead of 70, the device is in use
   sudo i2cdetect -y 1
   ```
   If you see `UU` at address 70, another process is using the display.

5. **Test Python I2C Access**:
   ```bash
   python3 -c "
   try:
       import board
       import busio
       i2c = busio.I2C(board.SCL, board.SDA)
       devices = i2c.scan()
       print('I2C devices found:', [hex(addr) for addr in devices])
       if 0x70 in devices:
           print('Display found at address 0x70')
       else:
           print('Display NOT found - check connections')
   except Exception as e:
       print('I2C error:', e)
   "
   ```

6. **Common Solutions**:
   - **No devices found**: Check power and ground connections, ensure both 5V (VIN) and 3.3V (IO) are connected
   - **Permission denied**: Add user to i2c group: `sudo usermod -a -G i2c $USER` then logout/login
   - **Device busy**: Stop any running clock processes: `sudo systemctl stop rpi-clock.service`
   - **Wrong address**: Some displays may use address 0x71 instead of 0x70
   - **Missing 3.3V**: The display requires both 5V (VIN) and 3.3V (IO) connections to function

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






