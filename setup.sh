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

echo ""
echo "Step 1: Updating package lists..."
sudo apt update

echo ""
echo "Step 2: Installing Python dependencies..."
sudo apt install -y python3-pip

# Install only the required Python packages
pip3 install --break-system-packages adafruit-circuitpython-ht16k33 requests ntplib

echo ""
echo "Step 3: Installing GPS daemon and clients..."
sudo apt install -y gpsd gpsd-clients

echo ""
echo "Step 4: Installing time synchronization software..."
sudo apt install -y chrony

echo ""
echo "Step 5: Configuring GPS daemon..."

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
echo "Step 6: Configuring chrony for GPS time synchronization..."

# Backup original chrony.conf
sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.backup

# Install optimized chrony configuration
sudo cp chrony.conf /etc/chrony/chrony.conf

# Restart chrony
sudo systemctl restart chrony

echo ""
echo "Step 7: Installing RPI-Clock files..."

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

echo ""
echo "Step 8: Creating systemd service for RPI-Clock..."

# Get current user for service
USER_NAME=$(whoami)

# Create systemd service file
sudo tee /etc/systemd/system/rpi-clock.service > /dev/null <<EOF
[Unit]
Description=RPI Clock
After=network.target gpsd.service

[Service]
Type=simple
User=$USER_NAME
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
echo "Step 9: Starting services..."

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
echo "Display Test:"
echo "The 7-segment display should now be showing the current time."
echo "If the display is blank, check the troubleshooting guide."
echo ""
echo "Next steps:"
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
