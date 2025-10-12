#!/bin/bash

# RPI-Clock Setup Script
# This script automates the installation and configuration of the RPI-Clock project

set -e  # Exit on any error

# Define color codes for better terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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
    echo "Installing adafruit-blinka..."
    pip3 install --user adafruit-blinka 2>/dev/null || echo "adafruit-blinka installation skipped (externally managed environment)"
else
    echo "adafruit-blinka already installed"
fi

if ! python_module_available adafruit_ht16k33; then
    echo "Installing adafruit-circuitpython-ht16k33..."
    pip3 install --user adafruit-circuitpython-ht16k33 2>/dev/null || echo "adafruit-circuitpython-ht16k33 installation skipped (externally managed environment)"
else
    echo "adafruit-circuitpython-ht16k33 already installed"
fi

# Install development tools (optional - may fail on externally managed environments)
echo "Installing Python development tools..."
if ! python_module_available flake8; then
    echo "Attempting to install flake8 (may fail on externally managed environments)..."
    pip3 install --user flake8 2>/dev/null || echo "flake8 installation skipped (externally managed environment)"
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
    echo "Installing adafruit-blinka for root..."
    sudo pip3 install adafruit-blinka 2>/dev/null || echo "adafruit-blinka root installation skipped (externally managed environment)"
else
    echo "adafruit-blinka already installed for root"
fi

if ! sudo python3 -c "import adafruit_ht16k33" 2>/dev/null; then
    echo "Installing adafruit-circuitpython-ht16k33 for root..."
    sudo pip3 install adafruit-circuitpython-ht16k33 2>/dev/null || echo "adafruit-circuitpython-ht16k33 root installation skipped (externally managed environment)"
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

# Install PPS tools for GPS precision timing
if ! package_installed pps-tools; then
    sudo apt install -y pps-tools
else
    echo "pps-tools already installed"
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

# Enable PPS overlay for GPS precision timing
if grep -q "dtoverlay=pps-gpio" /boot/firmware/config.txt; then
    echo "PPS overlay already enabled"
else
    echo "Enabling PPS overlay for GPS precision timing..."
    sudo sed -i '/dtoverlay=disable-bt/a dtoverlay=pps-gpio,gpiopin=18' /boot/firmware/config.txt
fi

# Load PPS modules for GPS precision timing
echo "Loading PPS modules..."
if ! lsmod | grep -q pps_ldisc; then
    echo "Loading pps_ldisc module..."
    sudo modprobe pps_ldisc
else
    echo "pps_ldisc module already loaded"
fi

# Add pps_ldisc to modules for auto-loading at boot
if ! grep -q "pps_ldisc" /etc/modules; then
    echo "Adding pps_ldisc to /etc/modules for auto-loading..."
    echo "pps_ldisc" | sudo tee -a /etc/modules
else
    echo "pps_ldisc already in /etc/modules"
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
ExecStart=/usr/sbin/gpsd -N -n /dev/ttyAMA0 /dev/pps0
Restart=always
RestartSec=5
User=gpsd
Group=dialout

[Install]
WantedBy=multi-user.target
EOF

# Configure GPSD defaults
echo "Configuring GPSD defaults..."
sudo tee /etc/default/gpsd > /dev/null <<EOF
# Devices gpsd should collect to at boot time.
# They need to be read/writeable, either by user gpsd or the group dialout.
DEVICES="/dev/ttyAMA0 /dev/pps0"

# Other options you want to pass to gpsd
GPSD_OPTIONS="-n"

# Automatically hot add/remove USB GPS devices via gpsdctl
USBAUTO="false"
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
echo "Step 11: Validating installation..."

# Validate GPS daemon is running
if systemctl is-active --quiet gpsd.service; then
    echo -e "${GREEN}✓ GPS daemon (gpsd) is running${NC}"
else
    echo -e "${RED}✗ GPS daemon (gpsd) is not running${NC}"
    echo -e "  ${YELLOW}Run:${NC} ${GREEN}sudo systemctl status gpsd.service${NC}"
fi

# Validate chrony is running
if systemctl is-active --quiet chrony.service; then
    echo -e "${GREEN}✓ Chrony time synchronization is running${NC}"
else
    echo -e "${RED}✗ Chrony time synchronization is not running${NC}"
    echo -e "  ${YELLOW}Run:${NC} ${GREEN}sudo systemctl status chrony.service${NC}"
fi

# Validate RPI-Clock service is running
if systemctl is-active --quiet rpi-clock.service; then
    echo -e "${GREEN}✓ RPI-Clock service is running${NC}"
else
    echo -e "${RED}✗ RPI-Clock service is not running${NC}"
    echo -e "  ${YELLOW}Run:${NC} ${GREEN}sudo systemctl status rpi-clock.service${NC}"
fi

# Validate GPS device exists
if [[ -e /dev/ttyAMA0 ]]; then
    echo -e "${GREEN}✓ GPS device /dev/ttyAMA0 exists${NC}"
else
    echo -e "${RED}✗ GPS device /dev/ttyAMA0 not found${NC}"
    echo -e "  ${YELLOW}This may require a reboot to activate UART configuration${NC}"
fi

# Validate PPS device exists
if [[ -e /dev/pps0 ]]; then
    echo -e "${GREEN}✓ PPS device /dev/pps0 exists${NC}"
else
    echo -e "${RED}✗ PPS device /dev/pps0 not found${NC}"
    echo -e "  ${YELLOW}This may require a reboot to activate PPS configuration${NC}"
fi

# Validate I2C is enabled
if i2c_enabled; then
    echo -e "${GREEN}✓ I2C interface is enabled${NC}"
else
    echo -e "${RED}✗ I2C interface is not enabled${NC}"
    echo -e "  ${YELLOW}Run:${NC} ${GREEN}sudo raspi-config nonint do_i2c 0${NC}"
fi

# Validate user groups
if user_in_i2c_group; then
    echo -e "${GREEN}✓ User is in i2c group${NC}"
else
    echo -e "${RED}✗ User is not in i2c group${NC}"
    echo -e "  ${YELLOW}Run:${NC} ${GREEN}sudo usermod -a -G i2c $USER${NC}"
fi

if user_in_gpio_group; then
    echo -e "${GREEN}✓ User is in gpio group${NC}"
else
    echo -e "${RED}✗ User is not in gpio group${NC}"
    echo -e "  ${YELLOW}Run:${NC} ${GREEN}sudo usermod -a -G gpio $USER${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}Setup completed successfully!${NC}"
echo ""
echo -e "${CYAN}Services started:${NC}"
echo -e "${WHITE}-${NC} ${GREEN}GPS daemon (gpsd)${NC}"
echo -e "${WHITE}-${NC} ${GREEN}RPI-Clock service${NC}"
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

# Check if UART was enabled, Bluetooth disabled, or PPS overlay added
if ! grep -q "enable_uart=1" /boot/firmware/config.txt || ! grep -q "dtoverlay=disable-bt" /boot/firmware/config.txt || ! grep -q "dtoverlay=pps-gpio" /boot/firmware/config.txt; then
    REBOOT_NEEDED=true
    REBOOT_REASONS+=("UART enabled, Bluetooth disabled, and PPS overlay added for GPS HAT")
fi

if [[ "$REBOOT_NEEDED" == "true" ]]; then
    echo ""
    echo -e "${RED}${BOLD}IMPORTANT: Reboot Required${NC}"
    echo -e "${RED}==========================${NC}"
    echo -e "${YELLOW}The following changes require a reboot to activate:${NC}"
    for reason in "${REBOOT_REASONS[@]}"; do
        echo -e "${WHITE}-${NC} ${CYAN}$reason${NC}"
    done
    echo ""
    echo -e "${GREEN}After reboot:${NC}"
    echo -e "${WHITE}-${NC} The GPS HAT will be detected on ${GREEN}/dev/ttyAMA0${NC}"
    echo -e "${WHITE}-${NC} The 7-segment display should show the current time"
    echo -e "${WHITE}-${NC} GPS time synchronization will be available"
    echo ""
    if prompt_yes_no "Do you want to reboot now to activate all changes?"; then
        echo -e "${YELLOW}Rebooting in 5 seconds...${NC}"
        sleep 5
        sudo reboot
    else
        echo ""
        echo -e "${YELLOW}Manual reboot required:${NC}"
        echo -e "${GREEN}sudo reboot${NC}"
        echo ""
        echo -e "${GREEN}After reboot:${NC}"
        echo -e "${WHITE}-${NC} GPS HAT will be available on ${GREEN}/dev/ttyAMA0${NC}"
        echo -e "${WHITE}-${NC} The 7-segment display should show the current time"
        echo -e "${WHITE}-${NC} If the display is blank, check the troubleshooting guide in ${BLUE}README.md${NC}"
    fi
else
    echo ""
    echo -e "${GREEN}✓ All interfaces already configured - no reboot required!${NC}"
fi
echo ""
echo -e "${CYAN}${BOLD}Next steps after reboot:${NC}"
echo -e "${WHITE}1.${NC} ${YELLOW}Edit config.ini with your OpenWeatherMap API key and ZIP code:${NC}"
echo -e "   ${GREEN}sudo nano /opt/rpi-clock/config.ini${NC}"
echo -e "   ${WHITE}-${NC} Replace ${RED}'XXXXXXXX'${NC} with your actual ${BLUE}OpenWeatherMap API key${NC}"
echo -e "   ${WHITE}-${NC} Replace ${RED}'90210'${NC} with your actual ${BLUE}ZIP code${NC}"
echo -e "${WHITE}2.${NC} ${YELLOW}Ensure your GPS antenna has a clear view of the sky${NC}"
echo -e "${WHITE}3.${NC} ${YELLOW}Test GPS connection:${NC} ${GREEN}cgps -s${NC}"
echo -e "${WHITE}4.${NC} ${YELLOW}Check GPS HAT detection:${NC} ${GREEN}ls -la /dev/ttyAMA*${NC}"
echo -e "${WHITE}5.${NC} ${YELLOW}Check chrony sources:${NC} ${GREEN}chronyc sources${NC}"
echo -e "${WHITE}6.${NC} ${YELLOW}Check clock status:${NC} ${GREEN}sudo systemctl status rpi-clock${NC}"
echo -e "${WHITE}7.${NC} ${YELLOW}View clock logs:${NC} ${GREEN}sudo journalctl -u rpi-clock -f${NC}"
echo ""
echo -e "${RED}${BOLD}IMPORTANT:${NC} ${YELLOW}The clock will not display weather data until you:${NC}"
echo -e "${WHITE}-${NC} Get a free API key from ${BLUE}https://openweathermap.org/api_keys/${NC}"
echo -e "${WHITE}-${NC} Update ${GREEN}/opt/rpi-clock/config.ini${NC} with your API key and ZIP code"
echo -e "${WHITE}-${NC} Restart the service: ${GREEN}sudo systemctl restart rpi-clock${NC}"
echo ""
echo -e "${GREEN}✓${NC} The clock will automatically start on boot."
echo -e "${GREEN}✓${NC} GPS HAT will be available on ${GREEN}/dev/ttyAMA0${NC} after reboot."
echo -e "${CYAN}ℹ${NC} For troubleshooting, see the ${BLUE}README.md${NC} file."
