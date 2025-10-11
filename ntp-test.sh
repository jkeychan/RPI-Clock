#!/bin/bash

# NTP Diagnostic Script
# This script helps diagnose NTP time synchronization issues

echo "RPI-Clock NTP Diagnostic Script"
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

echo "Step 1: Checking chrony service..."
echo "----------------------------------"
if systemctl is-active --quiet chrony.service; then
    echo "✓ chrony.service is running"
else
    echo "✗ chrony.service is NOT running"
    echo "  Run: sudo systemctl start chrony.service"
fi

if systemctl is-enabled --quiet chrony.service; then
    echo "✓ chrony.service is enabled"
else
    echo "✗ chrony.service is NOT enabled"
    echo "  Run: sudo systemctl enable chrony.service"
fi

echo ""
echo "Step 2: Checking chrony configuration..."
echo "---------------------------------------"
if [[ -f /etc/chrony/chrony.conf ]]; then
    echo "✓ chrony.conf exists"
    
    # Check for GPS reference
    if grep -q "refclock SHM" /etc/chrony/chrony.conf; then
        echo "✓ GPS reference clock configured"
    else
        echo "✗ GPS reference clock NOT configured"
        echo "  Check chrony.conf for 'refclock SHM 0'"
    fi
    
    # Check for upstream servers
    if grep -q "server.*pool.ntp.org" /etc/chrony/chrony.conf; then
        echo "✓ Upstream NTP servers configured"
    else
        echo "✗ Upstream NTP servers NOT configured"
        echo "  Check chrony.conf for server entries"
    fi
else
    echo "✗ chrony.conf NOT found"
    echo "  Run: sudo apt install chrony"
fi

echo ""
echo "Step 3: Testing chrony client tools..."
echo "-------------------------------------"
if command_exists chronyc; then
    echo "✓ chronyc is available"
else
    echo "✗ chronyc is NOT available"
    echo "  Run: sudo apt install chrony"
fi

echo ""
echo "Step 4: Checking chrony sources..."
echo "---------------------------------"
if command_exists chronyc; then
    echo "Current chrony sources:"
    chronyc sources -v 2>/dev/null || echo "Failed to get chrony sources"
    
    echo ""
    echo "Source statistics:"
    chronyc sourcestats 2>/dev/null || echo "Failed to get source statistics"
else
    echo "Cannot check sources - chronyc not available"
fi

echo ""
echo "Step 5: Checking chrony tracking..."
echo "----------------------------------"
if command_exists chronyc; then
    echo "Chrony tracking information:"
    chronyc tracking 2>/dev/null || echo "Failed to get tracking information"
    
    echo ""
    echo "System clock status:"
    chronyc makestep 2>/dev/null || echo "Failed to check clock status"
else
    echo "Cannot check tracking - chronyc not available"
fi

echo ""
echo "Step 6: Testing NTP connectivity..."
echo "----------------------------------"
if command_exists ntpdate; then
    echo "Testing NTP connectivity to pool.ntp.org..."
    ntpdate -q pool.ntp.org 2>/dev/null || echo "NTP connectivity test failed"
else
    echo "Cannot test NTP connectivity - ntpdate not available"
    echo "  Run: sudo apt install ntpdate"
fi

echo ""
echo "Step 7: Checking system time..."
echo "------------------------------"
echo "System time: $(date)"
echo "UTC time: $(date -u)"
echo "System uptime: $(uptime -p 2>/dev/null || uptime)"

if command_exists timedatectl; then
    echo ""
    echo "System time configuration:"
    timedatectl status 2>/dev/null || echo "Failed to get time configuration"
fi

echo ""
echo "Step 8: Checking time synchronization status..."
echo "----------------------------------------------"
if command_exists timedatectl; then
    echo "NTP synchronization status:"
    timedatectl show --property=NTP --value 2>/dev/null || echo "Unknown"
    
    echo "Time synchronization status:"
    timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo "Unknown"
else
    echo "Cannot check synchronization status - timedatectl not available"
fi

echo ""
echo "Step 9: Testing GPS time source..."
echo "----------------------------------"
if command_exists chronyc; then
    echo "Checking GPS time source..."
    chronyc sources | grep -E "(GPS|SHM)" | head -5
    
    echo ""
    echo "GPS source details:"
    chronyc sourcestats | grep -E "(GPS|SHM)" | head -5
else
    echo "Cannot check GPS time source - chronyc not available"
fi

echo ""
echo "Step 10: Checking chrony logs..."
echo "--------------------------------"
if [[ -f /var/log/chrony/chrony.log ]]; then
    echo "Recent chrony log entries:"
    tail -10 /var/log/chrony/chrony.log 2>/dev/null || echo "Cannot read chrony log"
else
    echo "Chrony log file not found"
fi

echo ""
echo "Step 11: Testing public time serving..."
echo "--------------------------------------"
if command_exists netstat; then
    echo "Checking if chrony is serving time publicly:"
    netstat -ulnp | grep :123 || echo "Chrony not serving on port 123"
else
    echo "Cannot check port 123 - netstat not available"
fi

echo ""
echo "Diagnostic complete!"
echo "==================="
echo ""
echo "Troubleshooting tips:"
echo "1. Check GPS fix: ./gps-test.sh"
echo "2. Verify chrony configuration: sudo nano /etc/chrony/chrony.conf"
echo "3. Restart chrony: sudo systemctl restart chrony"
echo "4. Check chrony sources: chronyc sources -v"
echo "5. Force time sync: sudo chronyc makestep"
echo "6. Check system logs: sudo journalctl -u chrony -f"
echo "7. Verify GPS daemon: sudo systemctl status gpsd"
echo ""
echo "For more help, see TROUBLESHOOTING.md"
