#!/bin/bash

# RPI-Clock Setup Script
# This script automates the installation and configuration of the RPI-Clock project

set -e  # Exit on any error

echo "RPI-Clock Setup Script"
echo "======================"
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user."
   echo "The script will prompt for sudo when needed."
   exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for user input
prompt_yes_no() {
    while true; do
        read -r -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

echo "This script will:"
echo "1. Update package lists"
echo "2. Install Python dependencies"
echo "3. Install GPS daemon (gpsd)"
echo "4. Install time synchronization software (chrony)"
echo "5. Configure GPS daemon"
echo "6. Configure chrony for GPS time sync"
echo "7. Create systemd service for auto-start"
echo ""

if ! prompt_yes_no "Do you want to continue?"; then
    echo "Setup cancelled."
    exit 0
fi

# Function to check if package is installed
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Function to check if Python module is available
python_module_available() {
    python3 -c "import $1" 2>/dev/null
}

# Function to check if I2C is enabled
i2c_enabled() {
    raspi-config nonint get_i2c 2>/dev/null | grep -q "0"
}

# Function to check if user is in i2c group
user_in_i2c_group() {
    groups "$USER" | grep -q i2c
}

# Function to check if user is in gpio group
user_in_gpio_group() {
    groups "$USER" | grep -q gpio
}

echo ""
echo "Step 1: Updating package lists..."
sudo apt update

echo ""
echo "Step 2: Installing Python dependencies..."
if ! package_installed python3-pip; then
    sudo apt install -y python3-pip
else
    echo "python3-pip already installed"
fi

# Check and install Python packages
echo "Installing Python packages via apt (system-wide)..."
if ! package_installed python3-requests; then
    sudo apt install -y python3-requests
else
    echo "python3-requests already installed"
fi

if ! package_installed python3-ntplib; then
    sudo apt install -y python3-ntplib
else
    echo "python3-ntplib already installed"
fi

# Install Adafruit packages via pip (not available in apt)
echo "Installing Adafruit CircuitPython packages..."
if ! python_module_available board; then
    pip3 install --user adafruit-blinka
else
    echo "adafruit-blinka already installed"
fi

if ! python_module_available adafruit_ht16k33; then
    pip3 install --user adafruit-circuitpython-ht16k33
else
    echo "adafruit-circuitpython-ht16k33 already installed"
fi

# Install development tools
echo "Installing Python development tools..."
if ! python_module_available flake8; then
    pip3 install --user flake8
else
    echo "flake8 already installed"
fi

# Install shellcheck for bash script validation
if ! command_exists shellcheck; then
    echo "Installing shellcheck for bash script validation..."
    sudo apt install -y shellcheck
else
    echo "shellcheck already installed"
fi

# Also install for root (needed for systemd service)
echo "Installing Adafruit packages for root user..."
if ! sudo python3 -c "import board" 2>/dev/null; then
    sudo pip3 install adafruit-blinka
else
    echo "adafruit-blinka already installed for root"
fi

if ! sudo python3 -c "import adafruit_ht16k33" 2>/dev/null; then
    sudo pip3 install adafruit-circuitpython-ht16k33
else
    echo "adafruit-circuitpython-ht16k33 already installed for root"
fi

echo ""
echo "Step 3: Installing GPS daemon and clients..."
if ! package_installed gpsd; then
    sudo apt install -y gpsd gpsd-clients
else
    echo "gpsd already installed"
fi

echo ""
echo "Step 4: Installing time synchronization software..."
if ! package_installed chrony; then
    sudo apt install -y chrony
else
    echo "chrony already installed"
fi

echo ""
echo "Step 5: Configuring I2C interface for display..."

# Check if I2C is already enabled
I2C_WAS_ENABLED=true
if i2c_enabled; then
    echo "I2C interface already enabled"
else
    echo "Enabling I2C interface..."
    sudo raspi-config nonint do_i2c 0
    I2C_WAS_ENABLED=false
fi

# Configure serial port (disable login shell, enable hardware)
sudo raspi-config nonint do_serial 1

# Configure UART for GPS HAT
echo "Configuring UART interface for GPS HAT..."
if grep -q "enable_uart=1" /boot/firmware/config.txt; then
    echo "UART already enabled"
else
    echo "Enabling UART interface..."
    sudo sed -i 's/enable_uart=0/enable_uart=1/' /boot/firmware/config.txt
fi

# Disable Bluetooth to free up UART for GPS HAT
if grep -q "dtoverlay=disable-bt" /boot/firmware/config.txt; then
    echo "Bluetooth already disabled for GPS HAT"
else
    echo "Disabling Bluetooth to free UART for GPS HAT..."
    sudo sed -i '/enable_uart=1/a dtoverlay=disable-bt' /boot/firmware/config.txt
fi

# Install I2C tools
if ! package_installed i2c-tools; then
    sudo apt install -y i2c-tools
else
    echo "i2c-tools already installed"
fi

# Add user to i2c group
if user_in_i2c_group; then
    echo "User already in i2c group"
else
    echo "Adding user to i2c group..."
    sudo usermod -a -G i2c "$USER"
fi

# Add user to gpio group
if user_in_gpio_group; then
    echo "User already in gpio group"
else
    echo "Adding user to gpio group..."
    sudo usermod -a -G gpio "$USER"
fi

echo "I2C and GPIO interfaces configured successfully!"

echo ""
echo "Step 6: Configuring GPS daemon..."

# Stop and disable default gpsd service (idempotent)
echo "Configuring GPS daemon..."
if systemctl is-active --quiet gpsd.socket; then
    echo "Stopping default gpsd.socket service..."
    sudo systemctl stop gpsd.socket
fi
if systemctl is-enabled --quiet gpsd.socket; then
    echo "Disabling default gpsd.socket service..."
    sudo systemctl disable gpsd.socket
fi

# Create gpsd service file
sudo tee /etc/systemd/system/gpsd.service > /dev/null <<EOF
[Unit]
Description=GPS daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/gpsd -N -n /dev/ttyAMA0
Restart=always
RestartSec=5
User=gpsd
Group=dialout

[Install]
WantedBy=multi-user.target
EOF

# Enable and start gpsd (idempotent)
sudo systemctl daemon-reload
if ! systemctl is-enabled --quiet gpsd.service; then
    echo "Enabling gpsd.service..."
    sudo systemctl enable gpsd.service
else
    echo "gpsd.service already enabled"
fi

echo ""
echo "Step 7: Configuring chrony for GPS time synchronization..."

# Backup original chrony.conf (idempotent)
if [[ ! -f /etc/chrony/chrony.conf.backup ]]; then
    echo "Backing up original chrony.conf..."
    sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.backup
else
    echo "chrony.conf backup already exists"
fi

# Install optimized chrony configuration
echo "Installing optimized chrony configuration..."
sudo cp chrony.conf /etc/chrony/chrony.conf

# Restart chrony
echo "Restarting chrony service..."
sudo systemctl restart chrony

echo ""
echo "Step 8: Installing RPI-Clock files..."

# Create installation directory (idempotent)
sudo mkdir -p /opt/rpi-clock

# Copy project files
echo "Installing RPI-Clock files..."
sudo cp clock.py /opt/rpi-clock/
sudo cp config.ini /opt/rpi-clock/
sudo cp rpi-clock-logo.png /opt/rpi-clock/ 2>/dev/null || true
sudo cp rpi-clock.gif /opt/rpi-clock/ 2>/dev/null || true

# Copy diagnostic scripts
sudo cp i2c-test.sh /opt/rpi-clock/
sudo cp gps-test.sh /opt/rpi-clock/
sudo cp ntp-test.sh /opt/rpi-clock/

# Set proper permissions
echo "Setting file permissions..."
sudo chown -R root:root /opt/rpi-clock
sudo chmod 755 /opt/rpi-clock
sudo chmod 644 /opt/rpi-clock/*.py /opt/rpi-clock/*.ini /opt/rpi-clock/*.png /opt/rpi-clock/*.gif
sudo chmod 755 /opt/rpi-clock/*.sh

# Make config.ini editable by the user who ran the setup
sudo chown root:"$USER" /opt/rpi-clock/config.ini
sudo chmod 664 /opt/rpi-clock/config.ini

echo ""
echo "Step 9: Creating systemd service for RPI-Clock..."

# Create systemd service file (run as user with GPIO group access)
sudo tee /etc/systemd/system/rpi-clock.service > /dev/null <<EOF
[Unit]
Description=RPI Clock - GPS-synchronized timekeeper with weather display
Documentation=https://github.com/jkeychan/rpi-clock
After=network.target gpsd.service
Wants=gpsd.service

[Service]
Type=simple
User="$USER"
Group="$USER"
WorkingDirectory=/opt/rpi-clock
ExecStart=/usr/bin/python3 /opt/rpi-clock/clock.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/rpi-clock /tmp
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictSUIDSGID=true
MemoryDenyWriteExecute=true
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

# Resource limits
LimitNOFILE=1024
LimitNPROC=64

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=rpi-clock

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service (idempotent)
sudo systemctl daemon-reload
if ! systemctl is-enabled --quiet rpi-clock.service; then
    echo "Enabling rpi-clock.service..."
    sudo systemctl enable rpi-clock.service
else
    echo "rpi-clock.service already enabled"
fi

echo ""
echo "Step 10: Starting services..."

# Start GPS daemon (idempotent)
if ! systemctl is-active --quiet gpsd.service; then
    echo "Starting gpsd.service..."
    sudo systemctl start gpsd.service
else
    echo "gpsd.service already running"
fi

# Start RPI-Clock service (idempotent)
if ! systemctl is-active --quiet rpi-clock.service; then
    echo "Starting rpi-clock.service..."
    sudo systemctl start rpi-clock.service
else
    echo "rpi-clock.service already running"
fi

echo ""
echo "Setup completed successfully!"
echo ""
echo "Services started:"
echo "- GPS daemon (gpsd)"
echo "- RPI-Clock service"
# Check if reboot is needed
REBOOT_NEEDED=false
REBOOT_REASONS=()

if [[ "${I2C_WAS_ENABLED:-true}" == "false" ]]; then
    REBOOT_NEEDED=true
    REBOOT_REASONS+=("I2C interface enabled")
fi

if ! user_in_gpio_group; then
    REBOOT_NEEDED=true
    REBOOT_REASONS+=("User added to GPIO group")
fi

# Check if UART was enabled or Bluetooth disabled
if ! grep -q "enable_uart=1" /boot/firmware/config.txt || ! grep -q "dtoverlay=disable-bt" /boot/firmware/config.txt; then
    REBOOT_NEEDED=true
    REBOOT_REASONS+=("UART enabled and Bluetooth disabled for GPS HAT")
fi

if [[ "$REBOOT_NEEDED" == "true" ]]; then
    echo ""
    echo "IMPORTANT: Reboot Required"
    echo "=========================="
    echo "The following changes require a reboot to activate:"
    for reason in "${REBOOT_REASONS[@]}"; do
        echo "- $reason"
    done
    echo ""
    echo "After reboot:"
    echo "- The GPS HAT will be detected on /dev/ttyAMA0"
    echo "- The 7-segment display should show the current time"
    echo "- GPS time synchronization will be available"
    echo ""
    if prompt_yes_no "Do you want to reboot now to activate all changes?"; then
        echo "Rebooting in 5 seconds..."
        sleep 5
        sudo reboot
    else
        echo ""
        echo "Manual reboot required:"
        echo "sudo reboot"
        echo ""
        echo "After reboot:"
        echo "- GPS HAT will be available on /dev/ttyAMA0"
        echo "- The 7-segment display should show the current time"
        echo "- If the display is blank, check the troubleshooting guide in README.md"
    fi
else
    echo ""
    echo "All interfaces already configured - no reboot required!"
fi
echo ""
echo "Next steps after reboot:"
echo "1. Edit config.ini with your OpenWeatherMap API key and ZIP code:"
echo "   sudo nano /opt/rpi-clock/config.ini"
echo "2. Ensure your GPS antenna has a clear view of the sky"
echo "3. Test GPS connection: cgps -s"
echo "4. Check GPS HAT detection: ls -la /dev/ttyAMA*"
echo "5. Check chrony sources: chronyc sources"
echo "6. Check clock status: sudo systemctl status rpi-clock"
echo "7. View clock logs: sudo journalctl -u rpi-clock -f"
echo ""
echo "The clock will automatically start on boot."
echo "GPS HAT will be available on /dev/ttyAMA0 after reboot."
echo "For troubleshooting, see the README.md file."
