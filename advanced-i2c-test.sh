#!/bin/bash

# Advanced I2C Diagnostic Script
# This script performs deep I2C troubleshooting

echo "Advanced I2C Diagnostic Script"
echo "============================="
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user."
   echo "The script will prompt for sudo when needed."
   exit 1
fi

echo "Step 1: Check I2C bus status..."
echo "-------------------------------"
echo "Available I2C buses:"
sudo i2cdetect -l

echo ""
echo "Step 2: Test both I2C buses..."
echo "------------------------------"
echo "Testing I2C bus 0:"
sudo i2cdetect -y 0 2>/dev/null || echo "Bus 0 not available"

echo ""
echo "Testing I2C bus 1:"
sudo i2cdetect -y 1

echo ""
echo "Step 3: Check I2C device permissions..."
echo "---------------------------------------"
ls -la /dev/i2c*
echo ""
echo "Current user groups:"
groups
echo ""
echo "I2C group members:"
getent group i2c 2>/dev/null || echo "i2c group not found"

echo ""
echo "Step 4: Test I2C communication with different methods..."
echo "-------------------------------------------------------"

echo "Method 1: Direct i2cget test"
echo "Trying to read from address 0x70..."
sudo i2cget -y 1 0x70 0x00 2>/dev/null && echo "✓ Device responds at 0x70" || echo "✗ No response at 0x70"

echo ""
echo "Method 2: Test different addresses"
for addr in 70 71 72 73 74 75 76 77; do
    echo -n "Testing 0x$addr: "
    if sudo i2cget -y 1 0x$addr 0x00 2>/dev/null; then
        echo "✓ Responds"
    else
        echo "✗ No response"
    fi
done

echo ""
echo "Step 5: Check for I2C conflicts..."
echo "----------------------------------"
echo "Running processes that might use I2C:"
ps aux | grep -i i2c | grep -v grep
echo ""
echo "Systemd services that might use I2C:"
systemctl list-units --type=service | grep -i i2c

echo ""
echo "Step 6: Test I2C with Python (different methods)..."
echo "---------------------------------------------------"

echo "Method 1: CircuitPython"
python3 -c "
try:
    import board
    import busio
    print('✓ CircuitPython modules available')
    
    i2c = busio.I2C(board.SCL, board.SDA)
    devices = i2c.scan()
    print(f'CircuitPython scan: {[hex(addr) for addr in devices]}')
    
except Exception as e:
    print(f'✗ CircuitPython error: {e}')
"

echo ""
echo "Method 2: smbus (alternative I2C library)"
python3 -c "
try:
    import smbus
    print('✓ smbus module available')
    
    bus = smbus.SMBus(1)
    devices = []
    for addr in range(0x08, 0x78):
        try:
            bus.read_byte(addr)
            devices.append(hex(addr))
        except:
            pass
    
    print(f'smbus scan: {devices}')
    
except ImportError:
    print('✗ smbus not available - install with: sudo apt install python3-smbus')
except Exception as e:
    print(f'✗ smbus error: {e}')
"

echo ""
echo "Step 7: Check GPIO pin configuration..."
echo "--------------------------------------"
echo "Current GPIO configuration:"
if command -v gpio >/dev/null 2>&1; then
    gpio readall
else
    echo "gpio command not available"
    echo "Install with: sudo apt install wiringpi"
fi

echo ""
echo "Step 8: Test with different I2C settings..."
echo "-------------------------------------------"
echo "Current I2C configuration:"
cat /boot/config.txt | grep -i i2c || echo "No I2C config found in /boot/config.txt"

echo ""
echo "Step 9: Manual I2C test with delays..."
echo "-------------------------------------"
echo "Testing I2C with manual commands and delays..."

# Test with different approaches
echo "Test 1: Basic i2cdetect"
sudo i2cdetect -y 1

echo ""
echo "Test 2: i2cdetect with verbose output"
sudo i2cdetect -y -v 1

echo ""
echo "Test 3: Try to write to device"
echo "Attempting to write 0x01 to address 0x70..."
sudo i2cset -y 1 0x70 0x00 0x01 2>/dev/null && echo "✓ Write successful" || echo "✗ Write failed"

echo ""
echo "Test 4: Read back what we wrote"
echo "Reading from address 0x70..."
sudo i2cget -y 1 0x70 0x00 2>/dev/null && echo "✓ Read successful" || echo "✗ Read failed"

echo ""
echo "Step 10: Check for hardware issues..."
echo "------------------------------------"
echo "Hardware troubleshooting checklist:"
echo "1. ✓ Power connected (LED confirms this)"
echo "2. ✓ GND connected (LED confirms this)"
echo "3. ? SDA connected to GPIO 2 (pin 3)"
echo "4. ? SCL connected to GPIO 3 (pin 5)"
echo "5. ? Display address jumpers (if any)"
echo "6. ? Display I2C address (might be 0x71)"
echo ""
echo "Try these manual tests:"
echo "1. sudo i2cset -y 1 0x71 0x00 0x01"
echo "2. sudo i2cget -y 1 0x71 0x00"
echo "3. Check if display has address selection jumpers"
echo "4. Try connecting to different GPIO pins"
echo "5. Test with external 5V power supply"

echo ""
echo "Step 11: Alternative I2C pins test..."
echo "------------------------------------"
echo "If standard I2C pins don't work, try enabling I2C-0:"
echo "sudo raspi-config nonint do_i2c 0"
echo "This enables I2C on pins 27,28 instead of 3,5"

echo ""
echo "Diagnostic complete!"
echo "==================="
echo ""
echo "If no devices are found:"
echo "1. Check display address jumpers"
echo "2. Try address 0x71 instead of 0x70"
echo "3. Verify SDA/SCL connections"
echo "4. Try I2C-0 on pins 27,28"
echo "5. Test with external power supply"
