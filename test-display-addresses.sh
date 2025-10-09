#!/bin/bash

# Test Display Addresses Script
# This script tests different I2C addresses for the 7-segment display

echo "Testing Different I2C Addresses for 7-Segment Display"
echo "====================================================="
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user."
   echo "The script will prompt for sudo when needed."
   exit 1
fi

echo "Step 1: Test all possible I2C addresses..."
echo "----------------------------------------"
echo "Testing addresses 0x08 to 0x77..."

found_devices=()

for addr in {8..119}; do
    hex_addr=$(printf "0x%02x" $addr)
    if sudo i2cget -y 1 $hex_addr 0x00 2>/dev/null; then
        echo "✓ Device found at $hex_addr"
        found_devices+=($hex_addr)
    fi
done

echo ""
if [ ${#found_devices[@]} -eq 0 ]; then
    echo "✗ No I2C devices found on bus 1"
else
    echo "Found devices: ${found_devices[*]}"
fi

echo ""
echo "Step 2: Test common display addresses..."
echo "---------------------------------------"
common_addresses=(0x70 0x71 0x72 0x73 0x74 0x75 0x76 0x77)

for addr in "${common_addresses[@]}"; do
    echo -n "Testing $addr: "
    if sudo i2cget -y 1 $addr 0x00 2>/dev/null; then
        echo "✓ Responds"
        
        # Try to initialize display
        echo "  Attempting to initialize display at $addr..."
        sudo i2cset -y 1 $addr 0x00 0x01 2>/dev/null && echo "  ✓ Write successful" || echo "  ✗ Write failed"
        
        # Try to read back
        result=$(sudo i2cget -y 1 $addr 0x00 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "  ✓ Read back: $result"
        else
            echo "  ✗ Read failed"
        fi
    else
        echo "✗ No response"
    fi
done

echo ""
echo "Step 3: Test with Python using found addresses..."
echo "------------------------------------------------"
if [ ${#found_devices[@]} -gt 0 ]; then
    python3 -c "
import board
import busio
from adafruit_ht16k33.segments import Seg7x4

i2c = busio.I2C(board.SCL, board.SDA)
devices = i2c.scan()
print(f'Python scan found: {[hex(addr) for addr in devices]}')

for addr in devices:
    try:
        print(f'Testing display at 0x{addr:02x}...')
        display = Seg7x4(i2c, address=addr)
        display.brightness = 0.5
        display.fill(0)
        display.print('TEST')
        display.show()
        print(f'✓ Display at 0x{addr:02x} working!')
        display.fill(0)
        display.show()
        break
    except Exception as e:
        print(f'✗ Display at 0x{addr:02x} failed: {e}')
"
else
    echo "No devices found to test with Python"
fi

echo ""
echo "Step 4: Check display documentation..."
echo "------------------------------------"
echo "Common Adafruit 7-segment display addresses:"
echo "- Default: 0x70"
echo "- Alternative: 0x71 (if address jumper is soldered)"
echo "- Some displays: 0x72, 0x73"
echo ""
echo "If your display has address selection jumpers:"
echo "1. Check if any jumpers are soldered"
echo "2. Default (no jumpers) = 0x70"
echo "3. AD0 jumper = 0x71"
echo "4. AD1 jumper = 0x72"
echo "5. Both jumpers = 0x73"

echo ""
echo "Step 5: Manual address test..."
echo "------------------------------"
echo "If you suspect the address is 0x71, try:"
echo "sudo i2cset -y 1 0x71 0x00 0x01"
echo "sudo i2cget -y 1 0x71 0x00"
echo ""
echo "Then test with Python:"
echo "python3 -c \"
import board
import busio
from adafruit_ht16k33.segments import Seg7x4
i2c = busio.I2C(board.SCL, board.SDA)
display = Seg7x4(i2c, address=0x71)
display.brightness = 0.5
display.print('TEST')
display.show()
\""

echo ""
echo "Test complete!"
echo "============="
echo ""
echo "Next steps:"
echo "1. If devices found: Test with Python using the found address"
echo "2. If no devices: Check wiring and power"
echo "3. Try address 0x71 if 0x70 doesn't work"
echo "4. Check display for address selection jumpers"
