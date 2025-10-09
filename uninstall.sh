#!/bin/bash

# RPI-Clock Uninstall Script
# This script removes the RPI-Clock installation

set -e  # Exit on any error

echo "RPI-Clock Uninstall Script"
echo "=========================="
echo ""

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
echo "1. Stop and disable the rpi-clock service"
echo "2. Remove the systemd service file"
echo "3. Remove installed files from /opt/rpi-clock"
echo "4. Reload systemd configuration"
echo ""

if ! prompt_yes_no "Do you want to continue with uninstallation?"; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "Step 1: Stopping and disabling rpi-clock service..."
sudo systemctl stop rpi-clock.service 2>/dev/null || true
sudo systemctl disable rpi-clock.service 2>/dev/null || true

echo ""
echo "Step 2: Removing systemd service file..."
sudo rm -f /etc/systemd/system/rpi-clock.service

echo ""
echo "Step 3: Removing installed files..."
sudo rm -rf /opt/rpi-clock

echo ""
echo "Step 4: Reloading systemd configuration..."
sudo systemctl daemon-reload

echo ""
echo "Uninstall completed successfully!"
echo ""
echo "Note: The following packages were NOT removed automatically:"
echo "- gpsd and gpsd-clients"
echo "- chrony"
echo "- Python packages (adafruit-circuitpython-ht16k33, requests, etc.)"
echo ""
echo "If you want to remove these packages as well, run:"
echo "sudo apt remove gpsd gpsd-clients chrony"
echo "pip3 uninstall adafruit-circuitpython-ht16k33 requests configparser ntplib"
echo ""
echo "Be careful when removing these packages as they might be used by other projects."
