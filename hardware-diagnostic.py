#!/usr/bin/env python3
"""Hardware Diagnostic Script for RPI-Clock

This script performs comprehensive hardware diagnostics to help troubleshoot
display connection issues. It can be run independently of the main clock
application to verify hardware setup.

Usage:
    python3 hardware-diagnostic.py
    sudo python3 hardware-diagnostic.py  # For more detailed system checks
"""

import os
import sys
import time
import subprocess
from typing import List, Tuple, Optional


def print_header(title: str) -> None:
    """Print a formatted section header."""
    print(f"\n{title}")
    print("=" * len(title))


def print_step(step_num: int, description: str) -> None:
    """Print a formatted step."""
    print(f"\nStep {step_num}: {description}")
    print("-" * (len(f"Step {step_num}: {description}")))


def run_command(cmd: List[str], capture_output: bool = True) -> Tuple[int, str, str]:
    """Run a command and return exit code, stdout, stderr."""
    try:
        result = subprocess.run(
            cmd, 
            capture_output=capture_output, 
            text=True, 
            timeout=30
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)


def check_i2c_modules() -> bool:
    """Check if required I2C kernel modules are loaded."""
    print_step(1, "Checking I2C kernel modules")
    
    try:
        with open('/proc/modules', 'r') as f:
            modules = f.read()
        
        required_modules = ['i2c_dev', 'i2c_bcm2835']
        all_loaded = True
        
        for module in required_modules:
            if module in modules:
                print(f"✓ {module} module is loaded")
            else:
                print(f"✗ {module} module is NOT loaded")
                print(f"  Run: sudo modprobe {module}")
                all_loaded = False
        
        return all_loaded
        
    except Exception as e:
        print(f"✗ Cannot check I2C modules: {e}")
        return False


def check_i2c_device_files() -> bool:
    """Check if I2C device files exist."""
    print_step(2, "Checking I2C device files")
    
    i2c_devices = ['/dev/i2c-0', '/dev/i2c-1']
    found_devices = []
    
    for device in i2c_devices:
        if os.path.exists(device):
            print(f"✓ Found I2C device: {device}")
            found_devices.append(device)
        else:
            print(f"✗ I2C device not found: {device}")
    
    if not found_devices:
        print("✗ No I2C device files found")
        print("  I2C interface may not be enabled")
        print("  Run: sudo raspi-config nonint do_i2c 0")
        print("  Then reboot the system")
        return False
    
    return True


def check_i2c_tools() -> bool:
    """Check if I2C tools are installed."""
    print_step(3, "Checking I2C tools")
    
    tools = ['i2cdetect', 'i2cget', 'i2cset']
    all_available = True
    
    for tool in tools:
        exit_code, _, _ = run_command(['which', tool])
        if exit_code == 0:
            print(f"✓ {tool} is available")
        else:
            print(f"✗ {tool} is NOT available")
            print("  Run: sudo apt install i2c-tools")
            all_available = False
    
    return all_available


def scan_i2c_bus() -> Optional[List[int]]:
    """Scan I2C bus for devices."""
    print_step(4, "Scanning I2C bus for devices")
    
    # Try both I2C buses
    for bus_num in [0, 1]:
        print(f"\nScanning I2C bus {bus_num}...")
        exit_code, stdout, stderr = run_command(['i2cdetect', '-y', str(bus_num)])
        
        if exit_code == 0:
            print(f"Bus {bus_num} scan results:")
            print(stdout)
            
            # Parse devices from output
            devices = []
            lines = stdout.strip().split('\n')[1:]  # Skip header
            for line in lines:
                parts = line.split(':')
                if len(parts) > 1:
                    addr_part = parts[0].strip()
                    if addr_part.isdigit():
                        devices.append(int(addr_part))
                    elif addr_part.startswith('0x'):
                        devices.append(int(addr_part, 16))
            
            if devices:
                print(f"✓ Found devices on bus {bus_num}: {[hex(addr) for addr in devices]}")
                return devices
            else:
                print(f"✗ No devices found on bus {bus_num}")
        else:
            print(f"✗ Cannot scan bus {bus_num}: {stderr}")
    
    return None


def check_user_permissions() -> bool:
    """Check if user has I2C permissions."""
    print_step(5, "Checking user permissions")
    
    try:
        import grp
        i2c_group = grp.getgrnam('i2c')
        user_groups = os.getgroups()
        
        if i2c_group.gr_gid in user_groups:
            print("✓ User is in i2c group")
            return True
        else:
            print("✗ User is NOT in i2c group")
            print("  Run: sudo usermod -a -G i2c $USER")
            print("  Then logout and login again")
            return False
            
    except Exception as e:
        print(f"✗ Cannot check I2C permissions: {e}")
        return False


def test_python_i2c_access() -> bool:
    """Test Python I2C access."""
    print_step(6, "Testing Python I2C access")
    
    try:
        import board
        import busio
        print("✓ CircuitPython board and busio modules available")
        
        try:
            i2c = busio.I2C(board.SCL, board.SDA)
            print("✓ I2C interface created successfully")
            
            devices = i2c.scan()
            print(f"I2C devices found: {[hex(addr) for addr in devices]}")
            
            if 0x70 in devices:
                print("✓ Display found at address 0x70")
                return True
            else:
                print("✗ Display NOT found at address 0x70")
                print("  Check your wiring:")
                print("  - VIN (red) → Pi pin 2 (5V)")
                print("  - IO (orange) → Pi pin 1 (3.3V) - REQUIRED")
                print("  - GND (black) → Pi pin 6 (GND)")
                print("  - SDA (yellow) → Pi pin 3 (GPIO 2)")
                print("  - SCL (white) → Pi pin 5 (GPIO 3)")
                return False
                
        except OSError as e:
            if e.errno == 121:  # Remote I/O error
                print("✗ I2C Remote I/O error - device not responding")
                print("  This usually indicates a wiring problem")
            elif e.errno == 5:  # Input/output error
                print("✗ I2C Input/Output error")
                print("  Check I2C interface is enabled and user has permissions")
            else:
                print(f"✗ I2C communication error: {e}")
            return False
            
    except ImportError as e:
        print(f"✗ Missing Python modules: {e}")
        print("  Run: pip3 install --break-system-packages adafruit-circuitpython-ht16k33")
        return False
    except Exception as e:
        print(f"✗ Unexpected error testing Python I2C: {e}")
        return False


def test_display_initialization() -> bool:
    """Test display initialization."""
    print_step(7, "Testing display initialization")
    
    try:
        import board
        import busio
        from adafruit_ht16k33.segments import Seg7x4
        
        print("Attempting to initialize display...")
        i2c = busio.I2C(board.SCL, board.SDA)
        display = Seg7x4(i2c)
        
        print("✓ Display initialized successfully!")
        print("Testing display...")
        
        # Test display
        display.brightness = 0.5
        display.fill(0)
        display.print("TEST")
        display.show()
        
        print("✓ Display test completed")
        print("You should see \"TEST\" on your display")
        
        # Clear display
        display.fill(0)
        display.show()
        
        return True
        
    except ValueError as e:
        if "No I2C device at address" in str(e):
            print("✗ Display not found at expected address 0x70")
            print("  This indicates a wiring problem")
        else:
            print(f"✗ Display address error: {e}")
        return False
    except OSError as e:
        if e.errno == 121:  # Remote I/O error
            print("✗ I2C Remote I/O error during display initialization")
            print("  Device not responding - check wiring")
        elif e.errno == 5:  # Input/output error
            print("✗ I2C Input/Output error during display initialization")
            print("  Check I2C interface and permissions")
        else:
            print(f"✗ I2C communication error: {e}")
        return False
    except Exception as e:
        print(f"✗ Display test failed: {e}")
        return False


def check_running_processes() -> None:
    """Check for running clock processes."""
    print_step(8, "Checking for running clock processes")
    
    try:
        exit_code, stdout, stderr = run_command(['pgrep', '-f', 'clock.py'])
        if exit_code == 0:
            print("✓ Clock process is running:")
            print(stdout)
            print("\nTo stop the clock process:")
            print("sudo systemctl stop rpi-clock.service")
            print("or")
            print("pkill -f clock.py")
        else:
            print("✗ No clock process is running")
    except Exception as e:
        print(f"✗ Cannot check running processes: {e}")


def print_wiring_guide() -> None:
    """Print detailed wiring guide."""
    print_header("WIRING GUIDE")
    print("7-Segment Display to Raspberry Pi Connections:")
    print("")
    print("Display Wire → Pi Pin → Function")
    print("VIN (red)   → Pin 2  → 5V Power")
    print("IO (orange) → Pin 1  → 3.3V Power (REQUIRED)")
    print("GND (black) → Pin 6  → Ground")
    print("SDA (yellow)→ Pin 3  → GPIO 2 (I2C Data)")
    print("SCL (white) → Pin 5  → GPIO 3 (I2C Clock)")
    print("")
    print("IMPORTANT NOTES:")
    print("- Both VIN (5V) and IO (3.3V) must be connected")
    print("- IO connection is REQUIRED for proper operation")
    print("- Ensure all connections are secure")
    print("- Check for loose wires or cold solder joints")


def print_troubleshooting_steps() -> None:
    """Print troubleshooting steps."""
    print_header("TROUBLESHOOTING STEPS")
    print("1. Check physical connections:")
    print("   - Ensure all wires are securely connected")
    print("   - Verify both 5V (VIN) and 3.3V (IO) are connected")
    print("   - Check for damaged wires or connectors")
    print("")
    print("2. Verify I2C is enabled:")
    print("   sudo raspi-config nonint do_i2c 0")
    print("   sudo reboot")
    print("")
    print("3. Check user permissions:")
    print("   sudo usermod -a -G i2c $USER")
    print("   # Then logout and login again")
    print("")
    print("4. Load I2C modules:")
    print("   sudo modprobe i2c_dev")
    print("   sudo modprobe i2c_bcm2835")
    print("")
    print("5. Test with i2c-tools:")
    print("   sudo i2cdetect -y 1")
    print("   # Should show device at address 70")
    print("")
    print("6. Check service logs:")
    print("   sudo journalctl -u rpi-clock.service -f")


def main():
    """Main diagnostic function."""
    print("RPI-Clock Hardware Diagnostic Script")
    print("====================================")
    print("This script will check your hardware setup and help")
    print("troubleshoot display connection issues.")
    
    # Run all diagnostic checks
    checks = [
        ("I2C Modules", check_i2c_modules),
        ("I2C Device Files", check_i2c_device_files),
        ("I2C Tools", check_i2c_tools),
        ("I2C Bus Scan", lambda: scan_i2c_bus() is not None),
        ("User Permissions", check_user_permissions),
        ("Python I2C Access", test_python_i2c_access),
        ("Display Initialization", test_display_initialization),
    ]
    
    results = []
    for check_name, check_func in checks:
        try:
            result = check_func()
            results.append((check_name, result))
        except Exception as e:
            print(f"✗ Error in {check_name}: {e}")
            results.append((check_name, False))
    
    # Check running processes (informational only)
    check_running_processes()
    
    # Print summary
    print_header("DIAGNOSTIC SUMMARY")
    passed = 0
    total = len(results)
    
    for check_name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status} {check_name}")
        if result:
            passed += 1
    
    print(f"\nOverall: {passed}/{total} checks passed")
    
    if passed == total:
        print("\n🎉 All checks passed! Your hardware setup looks good.")
        print("You can now run the clock application:")
        print("  python3 clock.py")
        print("  or")
        print("  sudo systemctl start rpi-clock.service")
    else:
        print("\n⚠️  Some checks failed. Please review the issues above.")
        print_wiring_guide()
        print_troubleshooting_steps()
    
    print("\nFor more detailed troubleshooting, see TROUBLESHOOTING.md")


if __name__ == "__main__":
    main()
