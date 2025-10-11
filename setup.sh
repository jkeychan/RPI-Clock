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
        read -p "$1 (y/n): " yn
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

echo ""
echo "Step 1: Checking and updating package lists..."
if ! package_installed apt; then
    sudo apt update
else
    echo "Package lists already up to date"
fi

echo ""
echo "Step 2: Installing Python dependencies..."
if ! package_installed python3-pip; then
    sudo apt install -y python3-pip
else
    echo "python3-pip already installed"
fi

# Check and install Python packages (for both user and root)
echo "Checking Python packages..."
python3 -c "import board" 2>/dev/null || pip3 install adafruit-blinka
python3 -c "import adafruit_ht16k33" 2>/dev/null || pip3 install adafruit-circuitpython-ht16k33
python3 -c "import requests" 2>/dev/null || pip3 install requests
python3 -c "import ntplib" 2>/dev/null || pip3 install ntplib

# Also install for root (needed for systemd service)
echo "Installing Python packages for root user..."
sudo python3 -c "import board" 2>/dev/null || sudo pip3 install adafruit-blinka
sudo python3 -c "import adafruit_ht16k33" 2>/dev/null || sudo pip3 install adafruit-circuitpython-ht16k33
sudo python3 -c "import requests" 2>/dev/null || sudo pip3 install requests
sudo python3 -c "import ntplib" 2>/dev/null || sudo pip3 install ntplib

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
echo "Enabling I2C interface..."

# Enable I2C interface
sudo raspi-config nonint do_i2c 0

# Configure serial port (disable login shell, enable hardware)
sudo raspi-config nonint do_serial 1

# Install I2C tools
if ! package_installed i2c-tools; then
    sudo apt install -y i2c-tools
else
    echo "i2c-tools already installed"
fi

# Add user to i2c group
sudo usermod -a -G i2c $USER

echo "I2C interface configured successfully!"
echo "Note: A reboot will be required after setup to activate I2C."

echo ""
echo "Step 6: Configuring GPS daemon..."

# Stop and disable default gpsd service
sudo systemctl stop gpsd.socket 2>/dev/null || true
sudo systemctl disable gpsd.socket 2>/dev/null || true

# Create gpsd service file
sudo tee /etc/systemd/system/gpsd.service > /dev/null <<EOF
[Unit]
Description=GPS daemon
After=multi-user.target

[Service]
Type=forking
ExecStart=/usr/sbin/gpsd /dev/serial0 -F /var/run/gpsd.sock
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start gpsd
sudo systemctl daemon-reload
sudo systemctl enable gpsd.service

echo ""
echo "Step 7: Configuring chrony for GPS time synchronization..."

# Backup original chrony.conf
sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.backup

# Install optimized chrony configuration
sudo cp chrony.conf /etc/chrony/chrony.conf

# Restart chrony
sudo systemctl restart chrony

echo ""
echo "Step 8: Installing RPI-Clock files..."

# Create installation directory
sudo mkdir -p /opt/rpi-clock

# Copy project files
sudo cp clock.py /opt/rpi-clock/
sudo cp config.ini /opt/rpi-clock/
sudo cp rpi-clock-logo.png /opt/rpi-clock/ 2>/dev/null || true
sudo cp rpi-clock.gif /opt/rpi-clock/ 2>/dev/null || true

# Set proper permissions
sudo chown -R root:root /opt/rpi-clock
sudo chmod 755 /opt/rpi-clock
sudo chmod 644 /opt/rpi-clock/*

# Make config.ini editable by the user who ran the setup
sudo chown root:$USER /opt/rpi-clock/config.ini
sudo chmod 664 /opt/rpi-clock/config.ini

echo ""
echo "Step 9: Creating systemd service for RPI-Clock..."

# Create systemd service file (run as root for GPIO access)
sudo tee /etc/systemd/system/rpi-clock.service > /dev/null <<EOF
[Unit]
Description=RPI Clock
After=network.target gpsd.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rpi-clock
ExecStart=/usr/bin/python3 /opt/rpi-clock/clock.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable rpi-clock.service

echo ""
echo "Step 10: Starting services..."

# Start GPS daemon
sudo systemctl start gpsd.service

# Start RPI-Clock service
sudo systemctl start rpi-clock.service

echo ""
echo "Setup completed successfully!"
echo ""
echo "Services started:"
echo "- GPS daemon (gpsd)"
echo "- RPI-Clock service"
echo ""
echo "IMPORTANT: Reboot Required"
echo "=========================="
echo "I2C interface has been enabled but requires a reboot to activate."
echo "The display will work after rebooting."
echo ""
if prompt_yes_no "Do you want to reboot now to activate I2C?"; then
    echo "Rebooting in 5 seconds..."
    echo "After reboot, the 7-segment display should show the current time."
    sleep 5
    sudo reboot
else
    echo ""
    echo "Manual reboot required:"
    echo "sudo reboot"
    echo ""
    echo "After reboot:"
    echo "- The 7-segment display should show the current time"
    echo "- If the display is blank, check the troubleshooting guide in README.md"
fi
echo ""
echo "Next steps after reboot:"
echo "1. Edit config.ini with your OpenWeatherMap API key and ZIP code:"
echo "   sudo nano /opt/rpi-clock/config.ini"
echo "2. Ensure your GPS antenna has a clear view of the sky"
echo "3. Test GPS connection: cgps -s"
echo "4. Check chrony sources: chronyc sources"
echo "5. Check clock status: sudo systemctl status rpi-clock"
echo "6. View clock logs: sudo journalctl -u rpi-clock -f"
echo ""
echo "The clock will automatically start on boot."
echo "For troubleshooting, see the README.md file."
