#!/bin/bash

# Wiring Diagnostic Script for 7-Segment Display
# This script helps diagnose wiring issues with the Adafruit 7-segment display

echo "7-Segment Display Wiring Diagnostic"
echo "=================================="
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user."
   echo "The script will prompt for sudo when needed."
   exit 1
fi

echo "Step 1: Verify I2C is working..."
echo "--------------------------------"
if lsmod | grep -q i2c_dev; then
    echo "✓ i2c_dev module loaded"
else
    echo "✗ i2c_dev module not loaded"
    exit 1
fi

if lsmod | grep -q i2c_bcm2835; then
    echo "✓ i2c_bcm2835 module loaded"
else
    echo "✗ i2c_bcm2835 module not loaded"
    exit 1
fi

echo ""
echo "Step 2: Check I2C device files..."
echo "--------------------------------"
if ls /dev/i2c* >/dev/null 2>&1; then
    echo "✓ I2C device files found:"
    ls -la /dev/i2c*
else
    echo "✗ No I2C device files found"
    exit 1
fi

echo ""
echo "Step 3: Scan I2C bus..."
echo "----------------------"
echo "Scanning I2C bus 1 for devices..."
sudo i2cdetect -y 1
echo ""
echo "Expected: Device at address 70 (0x70) for 7-segment display"
echo "If you see nothing at 70, check your wiring"

echo ""
echo "Step 4: Check GPIO pin assignments..."
echo "-----------------------------------"
echo "Your display should be connected as follows:"
echo ""
echo "Display Backpack → Raspberry Pi GPIO"
echo "VCC (red wire)   → Pin 2  (5V)"
echo "GND (black wire) → Pin 6  (GND)"
echo "SDA (yellow wire)→ Pin 3  (GPIO 2, SDA)"
echo "SCL (white wire) → Pin 5  (GPIO 3, SCL)"
echo ""
echo "GPIO Pin Layout (looking at Pi with USB ports at bottom):"
echo "    3V3  (1) (2)  5V"
echo "  GPIO2  (3) (4)  5V"
echo "  GPIO3  (5) (6)  GND"
echo "  GPIO4  (7) (8)  GPIO14"
echo "    GND  (9) (10) GPIO15"
echo " GPIO17 (11) (12) GPIO18"
echo " GPIO27 (13) (14) GND"
echo " GPIO22 (15) (16) GPIO23"
echo "    3V3 (17) (18) GPIO24"
echo " GPIO10 (19) (20) GND"
echo "  GPIO9 (21) (22) GPIO25"
echo " GPIO11 (23) (24) GPIO8"
echo "    GND (25) (26) GPIO7"
echo ""

echo "Step 5: Test with different I2C addresses..."
echo "------------------------------------------"
echo "Some displays might use different addresses. Testing common addresses:"
echo ""

# Test different possible addresses
for addr in 70 71 72 73; do
    echo -n "Testing address 0x$addr: "
    if sudo i2cdetect -y 1 | grep -q "$addr"; then
        echo "✓ Found device"
    else
        echo "✗ No device"
    fi
done

echo ""
echo "Step 6: Check for power issues..."
echo "--------------------------------"
echo "Power troubleshooting:"
echo "1. Make sure VCC (red) is connected to 5V (pin 2)"
echo "2. Make sure GND (black) is connected to GND (pin 6)"
echo "3. Check that wires are making good contact"
echo "4. Try wiggling connections to see if device appears"
echo ""

echo "Step 7: Test with Python..."
echo "--------------------------"
python3 -c "
try:
    import board
    import busio
    print('✓ CircuitPython modules available')
    
    i2c = busio.I2C(board.SCL, board.SDA)
    devices = i2c.scan()
    print(f'I2C devices found: {[hex(addr) for addr in devices]}')
    
    if not devices:
        print('✗ No I2C devices found')
        print('')
        print('Common issues:')
        print('1. Wrong wiring - double-check connections')
        print('2. Loose connections - try wiggling wires')
        print('3. Wrong power - make sure 5V is connected')
        print('4. Display not powered - check LED brightness')
        print('5. Wrong I2C address - some displays use 0x71')
    else:
        print('✓ I2C communication working')
        
except Exception as e:
    print(f'✗ Python I2C error: {e}')
"

echo ""
echo "Step 8: Manual I2C test..."
echo "-------------------------"
echo "If Python test failed, try manual I2C commands:"
echo ""
echo "# Test I2C communication manually:"
echo "sudo i2cget -y 1 0x70 0x00"
echo ""
echo "# If that works, try:"
echo "sudo i2cset -y 1 0x70 0x00 0x01"
echo ""

echo "Step 9: Alternative connection test..."
echo "------------------------------------"
echo "If still not working, try these alternatives:"
echo ""
echo "1. Use different GPIO pins for I2C:"
echo "   - Enable I2C-0: sudo raspi-config nonint do_i2c 0"
echo "   - Use pins 27,28 instead of 3,5"
echo ""
echo "2. Check display address jumpers:"
echo "   - Some displays have address selection jumpers"
echo "   - Default is usually 0x70, but might be 0x71"
echo ""
echo "3. Test with external power:"
echo "   - Use external 5V supply instead of Pi 5V"
echo "   - Connect GND between Pi and external supply"
echo ""

echo "Diagnostic complete!"
echo "==================="
echo ""
echo "Next steps:"
echo "1. Double-check all wiring connections"
echo "2. Try wiggling connections while running i2cdetect"
echo "3. Test with different I2C address (0x71)"
echo "4. Check if display LEDs are lit (power indicator)"
echo "5. Try external power supply"
