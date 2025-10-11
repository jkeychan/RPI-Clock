#!/bin/bash

# I2C Display Diagnostic Script
# This script helps diagnose I2C display connection issues

echo "RPI-Clock I2C Diagnostic Script"
echo "==============================="
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user."
   echo "The script will prompt for sudo when needed."
   exit 1
fi

echo "Step 1: Checking I2C kernel modules..."
echo "--------------------------------------"
if lsmod | grep -q i2c_dev; then
    echo "✓ i2c_dev module is loaded"
else
    echo "✗ i2c_dev module is NOT loaded"
    echo "  Run: sudo modprobe i2c_dev"
fi

if lsmod | grep -q i2c_bcm2835; then
    echo "✓ i2c_bcm2835 module is loaded"
else
    echo "✗ i2c_bcm2835 module is NOT loaded"
    echo "  Run: sudo modprobe i2c_bcm2835"
fi

echo ""
echo "Step 2: Checking I2C device files..."
echo "------------------------------------"
if ls /dev/i2c* >/dev/null 2>&1; then
    echo "✓ I2C device files found:"
    ls -la /dev/i2c*
else
    echo "✗ No I2C device files found"
    echo "  I2C interface may not be enabled"
    echo "  Run: sudo raspi-config nonint do_i2c 0"
fi

echo ""
echo "Step 3: Checking I2C tools..."
echo "-----------------------------"
if command -v i2cdetect >/dev/null 2>&1; then
    echo "✓ i2cdetect is available"
else
    echo "✗ i2cdetect is NOT available"
    echo "  Run: sudo apt install i2c-tools"
fi

echo ""
echo "Step 4: Scanning I2C bus for devices..."
echo "---------------------------------------"
if command -v i2cdetect >/dev/null 2>&1; then
    echo "Scanning I2C bus 1..."
    sudo i2cdetect -y 1
    echo ""
    echo "Expected: Device at address 70 (0x70) for 7-segment display"
    echo "If you see 'UU' at 70, the device is in use by another process"
    echo "If you see nothing at 70, check your wiring"
else
    echo "Cannot scan I2C bus - i2cdetect not available"
fi

echo ""
echo "Step 5: Checking user permissions..."
echo "-----------------------------------"
if groups | grep -q i2c; then
    echo "✓ User is in i2c group"
else
    echo "✗ User is NOT in i2c group"
    echo "  Run: sudo usermod -a -G i2c $USER"
    echo "  Then logout and login again"
fi

echo ""
echo "Step 6: Testing Python I2C access..."
echo "------------------------------------"
python3 -c "
try:
    import board
    import busio
    print('✓ CircuitPython board and busio modules available')
    
    try:
        i2c = busio.I2C(board.SCL, board.SDA)
        print('✓ I2C interface created successfully')
        
        devices = i2c.scan()
        print(f'I2C devices found: {[hex(addr) for addr in devices]}')
        
        if 0x70 in devices:
            print('✓ Display found at address 0x70')
        else:
            print('✗ Display NOT found at address 0x70')
            print('  Check your wiring:')
            print('  - VIN (red) → Pi pin 2 (5V)')
            print('  - IO (orange) → Pi pin 1 (3.3V) - REQUIRED')
            print('  - GND (black) → Pi pin 6 (GND)')
            print('  - SDA (yellow) → Pi pin 3 (GPIO 2)')
            print('  - SCL (white) → Pi pin 5 (GPIO 3)')
            
    except Exception as e:
        print(f'✗ I2C communication error: {e}')
        print('  Possible causes:')
        print('  - I2C not enabled')
        print('  - Permission denied (user not in i2c group)')
        print('  - Hardware connection issues')
        
except ImportError as e:
    print(f'✗ Missing Python modules: {e}')
    print('  Run: pip3 install --break-system-packages adafruit-circuitpython-ht16k33')
"

echo ""
echo "Step 7: Checking for running clock processes..."
echo "----------------------------------------------"
if pgrep -f "clock.py" >/dev/null; then
    echo "✓ Clock process is running:"
    pgrep -af clock.py
    echo ""
    echo "To stop the clock process:"
    echo "sudo systemctl stop rpi-clock.service"
    echo "or"
    echo "pkill -f clock.py"
else
    echo "✗ No clock process is running"
fi

echo ""
echo "Step 8: Testing display with simple Python script..."
echo "--------------------------------------------------"
python3 -c "
try:
    import board
    import busio
    from adafruit_ht16k33.segments import Seg7x4
    
    print('Attempting to initialize display...')
    i2c = busio.I2C(board.SCL, board.SDA)
    display = Seg7x4(i2c)
    
    print('✓ Display initialized successfully!')
    print('Testing display...')
    
    # Test display
    display.brightness = 0.5
    display.fill(0)
    display.print('TEST')
    display.show()
    
    print('✓ Display test completed')
    print('You should see \"TEST\" on your display')
    
    # Clear display
    display.fill(0)
    display.show()
    
except Exception as e:
    print(f'✗ Display test failed: {e}')
    print('')
    print('Troubleshooting steps:')
    print('1. Check physical connections - ensure both 5V (VIN) and 3.3V (IO) are connected')
    print('2. Verify I2C is enabled: sudo raspi-config nonint do_i2c 0')
    print('3. Reboot after enabling I2C')
    print('4. Check user permissions: sudo usermod -a -G i2c $USER')
    print('5. Stop any running clock processes')
"

echo ""
echo "Diagnostic complete!"
echo "==================="
echo ""
echo "If the display test passed, your wiring is correct."
echo "If not, follow the troubleshooting steps above."
echo ""
echo "Next steps:"
echo "1. If display test passed: Run 'python3 clock.py'"
echo "2. If display test failed: Check wiring and I2C setup"
echo "3. Check service status: sudo systemctl status rpi-clock.service"
