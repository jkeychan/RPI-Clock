#!/bin/bash

# Create RPI-Clock Service Script
# This script creates the systemd service for RPI-Clock

echo "Creating RPI-Clock systemd service..."
echo "===================================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user."
   echo "The script will prompt for sudo when needed."
   exit 1
fi

# Get current user for service
USER_NAME=$(whoami)
echo "Service will run as user: $USER_NAME"

# Check if clock files exist
if [ ! -f "/opt/rpi-clock/clock.py" ]; then
    echo "Error: clock.py not found at /opt/rpi-clock/clock.py"
    echo "Please run the setup script first."
    exit 1
fi

# Create systemd service file
echo "Creating systemd service file..."
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

# Reload systemd and enable service
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Enabling rpi-clock service..."
sudo systemctl enable rpi-clock.service

echo "Starting rpi-clock service..."
sudo systemctl start rpi-clock.service

echo ""
echo "Service created and started successfully!"
echo ""
echo "Service status:"
sudo systemctl status rpi-clock.service --no-pager

echo ""
echo "To manage the service:"
echo "  Start:   sudo systemctl start rpi-clock.service"
echo "  Stop:    sudo systemctl stop rpi-clock.service"
echo "  Restart: sudo systemctl restart rpi-clock.service"
echo "  Status:  sudo systemctl status rpi-clock.service"
echo "  Logs:    sudo journalctl -u rpi-clock.service -f"
