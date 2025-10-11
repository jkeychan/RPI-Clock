#!/bin/bash

# GPS Diagnostic Script
# This script helps diagnose GPS connection and synchronization issues

echo "RPI-Clock GPS Diagnostic Script"
echo "==============================="
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

echo "Step 1: Checking GPS daemon service..."
echo "--------------------------------------"
if systemctl is-active --quiet gpsd.service; then
    echo "✓ gpsd.service is running"
else
    echo "✗ gpsd.service is NOT running"
    echo "  Run: sudo systemctl start gpsd.service"
fi

if systemctl is-enabled --quiet gpsd.service; then
    echo "✓ gpsd.service is enabled"
else
    echo "✗ gpsd.service is NOT enabled"
    echo "  Run: sudo systemctl enable gpsd.service"
fi

echo ""
echo "Step 2: Checking GPS hardware connection..."
echo "------------------------------------------"
if [[ -c /dev/ttyAMA0 ]]; then
    echo "✓ GPS HAT device /dev/ttyAMA0 exists (primary GPS interface)"
else
    echo "✗ GPS HAT device /dev/ttyAMA0 NOT found"
    echo "  Check GPS HAT connection and UART configuration"
    echo "  Run: sudo raspi-config nonint do_serial 1"
    echo "  Ensure UART is enabled: enable_uart=1 in /boot/firmware/config.txt"
    echo "  Disable Bluetooth: dtoverlay=disable-bt in /boot/firmware/config.txt"
fi

if [[ -c /dev/serial0 ]]; then
    echo "✓ Serial device /dev/serial0 exists (fallback interface)"
else
    echo "✗ Serial device /dev/serial0 NOT found"
fi

if [[ -c /dev/pps0 ]]; then
    echo "✓ PPS device /dev/pps0 exists (precision timing)"
else
    echo "✗ PPS device /dev/pps0 NOT found"
    echo "  PPS provides microsecond precision timing"
fi

echo ""
echo "Step 3: Checking GPS daemon socket..."
echo "------------------------------------"
if [[ -S /var/run/gpsd.sock ]]; then
    echo "✓ GPS daemon socket exists"
else
    echo "✗ GPS daemon socket NOT found"
    echo "  GPS daemon may not be running properly"
fi

echo ""
echo "Step 4: Testing GPS client tools..."
echo "----------------------------------"
if command_exists cgps; then
    echo "✓ cgps is available"
else
    echo "✗ cgps is NOT available"
    echo "  Run: sudo apt install gpsd-clients"
fi

if command_exists gpsmon; then
    echo "✓ gpsmon is available"
else
    echo "✗ gpsmon is NOT available"
    echo "  Run: sudo apt install gpsd-clients"
fi

echo ""
echo "Step 5: Testing GPS data reception..."
echo "------------------------------------"
if command_exists cgps; then
    echo "Testing GPS data reception (timeout: 10 seconds)..."
    timeout 10 cgps -s 2>/dev/null | head -20
    if [[ ${PIPESTATUS[0]} -eq 124 ]]; then
        echo "✗ GPS data reception timeout"
        echo "  Possible causes:"
        echo "  - GPS antenna not connected or damaged"
        echo "  - No clear view of sky"
        echo "  - GPS HAT not properly connected"
        echo "  - Cold start (wait 5-15 minutes)"
    else
        echo "✓ GPS data reception successful"
    fi
else
    echo "Cannot test GPS data - cgps not available"
fi

echo ""
echo "Step 6: Checking GPS fix status..."
echo "---------------------------------"
if command_exists gpsmon; then
    echo "Checking GPS fix status (timeout: 5 seconds)..."
    timeout 5 gpsmon 2>/dev/null | grep -E "(Fix|Status|Satellites)" | head -10
    if [[ ${PIPESTATUS[0]} -eq 124 ]]; then
        echo "✗ GPS fix check timeout"
    else
        echo "✓ GPS fix check completed"
    fi
else
    echo "Cannot check GPS fix - gpsmon not available"
fi

echo ""
echo "Step 7: Testing GPS time synchronization..."
echo "------------------------------------------"
if command_exists gpspipe; then
    echo "Testing GPS time data (timeout: 5 seconds)..."
    timeout 5 gpspipe -r 2>/dev/null | grep -E "TPV|TIME" | head -5
    if [[ ${PIPESTATUS[0]} -eq 124 ]]; then
        echo "✗ GPS time data timeout"
    else
        echo "✓ GPS time data received"
    fi
else
    echo "Cannot test GPS time - gpspipe not available"
fi

echo ""
echo "Step 8: Checking chrony GPS integration..."
echo "------------------------------------------"
if command_exists chronyc; then
    echo "Checking chrony sources..."
    chronyc sources | grep -E "(GPS|SHM)" || echo "No GPS sources found in chrony"
    
    echo ""
    echo "Checking chrony tracking..."
    chronyc tracking | head -5
else
    echo "✗ chronyc not available"
    echo "  Run: sudo apt install chrony"
fi

echo ""
echo "Step 9: Checking system time synchronization..."
echo "---------------------------------------------"
echo "System time: $(date)"
echo "UTC time: $(date -u)"
echo "Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || echo 'Unknown')"

if command_exists timedatectl; then
    echo ""
    echo "Time synchronization status:"
    timedatectl status | grep -E "(NTP|synchronized|time)"
fi

echo ""
echo "Diagnostic complete!"
echo "==================="
echo ""
echo "Troubleshooting tips:"
echo "1. Ensure GPS antenna has clear view of sky"
echo "2. Wait 5-15 minutes for cold start GPS fix"
echo "3. Check all GPS HAT connections"
echo "4. Verify GPS antenna is not damaged"
echo "5. Test with external GPS antenna if available"
echo "6. Check chrony configuration: sudo nano /etc/chrony/chrony.conf"
echo "7. Restart services: sudo systemctl restart gpsd chrony"
echo ""
echo "For more help, see TROUBLESHOOTING.md"
