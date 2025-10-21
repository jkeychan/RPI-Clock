# RPI-Clock Troubleshooting Guide

This guide helps you diagnose and fix common issues with the RPI-Clock project.

## Diagnostic Scripts

The project includes three essential diagnostic scripts to help troubleshoot issues:

```bash
# Test I2C display connection
./i2c-test.sh

# Test GPS connection and synchronization  
./gps-test.sh

# Test NTP time synchronization
./ntp-test.sh
```

These scripts are installed to `/opt/rpi-clock/` and can be run from there. They provide detailed diagnostics and troubleshooting suggestions for each component.

## GPS Issues

### No GPS Fix

**Symptoms:**
- Clock shows incorrect time
- `cgps -s` shows "No fix" or "No GPS"
- `chronyc sources` shows no GPS source

**Solutions:**
1. **Check antenna placement**: Ensure GPS antenna has clear view of sky
2. **Wait for cold start**: First GPS fix can take 5-10 minutes
3. **Check connections**: Verify GPS HAT is properly connected
4. **Test GPS manually**:
   ```bash
   sudo gpsd /dev/serial0 -F /var/run/gpsd.sock
   cgps -s
   ```

### Slow GPS Fix

**Symptoms:**
- GPS takes longer than expected to get fix
- Intermittent GPS signal

**Solutions:**
1. **Use external antenna**: Indoor reception is poor with built-in antenna
2. **Check antenna cable**: Ensure SMA to uFL adapter is secure
3. **Position antenna**: Place near window or outside
4. **Wait longer**: Cold starts can take up to 15 minutes

### GPS Signal Quality Issues

**Symptoms:**
- GPS fix drops frequently
- Time drifts between GPS fixes

**Solutions:**
1. **Check antenna**: Replace damaged or poor quality antenna
2. **Improve placement**: Move antenna to better location
3. **Check interference**: Remove sources of RF interference
4. **Verify connections**: Check all cable connections

## Display Issues

### No Display Output

**Symptoms:**
- Display remains blank
- No characters appear on 7-segment display

**Solutions:**
1. **Check I2C interface**:
   ```bash
   sudo raspi-config
   # Interface Options > I2C > Yes
   sudo reboot
   ```

2. **Verify I2C detection**:
   ```bash
   sudo i2cdetect -y 1
   # Should show device at address 0x70
   ```

3. **Check connections**:
   - VCC → Pi 5V
   - GND → Pi GND
   - SDA → Pi SDA (GPIO 2)
   - SCL → Pi SCL (GPIO 3)
   - **COMMON ISSUE**: SDA and SCL wires are easily confused - try swapping them!

4. **Test display manually**:
   ```python
   import board
   import busio
   import adafruit_ht16k33.segments as segments
   
   i2c = busio.I2C(board.SCL, board.SDA)
   display = segments.Seg7x4(i2c)
   display.print("TEST")
   display.show()
   ```

### Wrong Characters on Display

**Symptoms:**
- Display shows incorrect characters
- Characters appear garbled

**Solutions:**
1. **Check SDA/SCL connections**: 
   - **COMMON ISSUE**: SDA and SCL wires are easily confused
   - Try swapping SDA (yellow) and SCL (white) wires
   - Correct wiring: SDA (yellow) → Pi pin 3 (GPIO 2), SCL (white) → Pi pin 5 (GPIO 3)
2. **Verify I2C address**: Ensure no address conflicts
3. **Check power**: Ensure stable 5V power supply
4. **Test with known good display**: Replace display if faulty

### Dim or Flickering Display

**Symptoms:**
- Display is too dim to read
- Display flickers or flashes

**Solutions:**
1. **Check power connections**: Ensure stable 5V supply
2. **Verify ground connection**: Check GND connection
3. **Check for loose connections**: Reseat all connectors
4. **Test with different power source**: Use external 5V supply

## Time Synchronization Issues

### Wrong Time Displayed

**Symptoms:**
- Clock shows incorrect time
- Time doesn't match GPS time

**Solutions:**
1. **Check GPS fix**: Ensure GPS has valid fix
   ```bash
   cgps -s
   ```

2. **Verify chrony sources**:
   ```bash
   chronyc sources
   # Should show GPS source with asterisk (*)
   ```

3. **Check chrony status**:
   ```bash
   chronyc tracking
   ```

4. **Restart services**:
   ```bash
   sudo systemctl restart gpsd
   sudo systemctl restart chrony
   ```

### Time Drift

**Symptoms:**
- Time gradually becomes incorrect
- Clock loses accuracy over time

**Solutions:**
1. **Check GPS signal quality**: Ensure consistent GPS fix
2. **Verify chrony configuration**: Check `/etc/chrony/chrony.conf`
3. **Monitor chrony tracking**:
   ```bash
   chronyc tracking
   # Look for low offset values
   ```

4. **Check system clock**:
   ```bash
   timedatectl status
   ```

### No Time Synchronization

**Symptoms:**
- Time never updates from GPS
- Chrony shows no sources

**Solutions:**
1. **Check gpsd service**:
   ```bash
   sudo systemctl status gpsd
   ```

2. **Verify GPS data flow**:
   ```bash
   gpsmon
   ```

3. **Check chrony configuration**:
   ```bash
   sudo nano /etc/chrony/chrony.conf
   # Ensure GPS reference is present
   ```

4. **Restart all services**:
   ```bash
   sudo systemctl restart gpsd
   sudo systemctl restart chrony
   ```

## Weather Issues

### No Weather Data

**Symptoms:**
- Display shows "----" for weather
- No temperature or humidity data

**Solutions:**
1. **Check internet connection**:
   ```bash
   ping -c 3 openweathermap.org
   ```

2. **Verify API key**: Check `config.ini` for valid API key
3. **Test API manually**:
   ```bash
   curl "http://api.openweathermap.org/data/2.5/weather?zip=90210&appid=YOUR_API_KEY"
   ```

4. **Check ZIP code**: Ensure ZIP code is correct in `config.ini`

### Wrong Weather Location

**Symptoms:**
- Weather data doesn't match your location
- Temperature seems incorrect for your area

**Solutions:**
1. **Update ZIP code**: Change ZIP code in `config.ini`
2. **Verify location**: Check OpenWeatherMap for your area
3. **Test with different ZIP**: Try nearby ZIP codes

### Weather Data Errors

**Symptoms:**
- Weather display shows errors
- Temperature values are unrealistic

**Solutions:**
1. **Check API response**: Test API call manually
2. **Verify API key permissions**: Ensure key has weather access
3. **Check network connectivity**: Ensure stable internet connection
4. **Update API key**: Generate new API key if needed

## System Issues

### Service Won't Start

**Symptoms:**
- `sudo systemctl start rpi-clock` fails
- Service shows as failed

**Solutions:**
1. **Check service status**:
   ```bash
   sudo systemctl status rpi-clock
   ```

2. **Check service logs**:
   ```bash
   sudo journalctl -u rpi-clock -f
   ```

3. **Verify file permissions**:
   ```bash
   ls -la clock.py
   ls -la config.ini
   ```

4. **Test manual execution**:
   ```bash
   python3 clock.py
   ```

### Permission Issues

**Symptoms:**
- "Permission denied" errors
- Can't access GPIO or I2C

**Solutions:**
1. **Add user to groups**:
   ```bash
   sudo usermod -a -G i2c,gpio $USER
   ```

2. **Check group membership**:
   ```bash
   groups $USER
   ```

3. **Restart session**: Log out and back in

### Python Import Errors

**Symptoms:**
- "Module not found" errors
- Import failures

**Solutions:**
1. **Install missing packages**:
   ```bash
   pip3 install adafruit-circuitpython-ht16k33 requests configparser ntplib
   ```

2. **Check Python version**:
   ```bash
   python3 --version
   # Should be 3.6 or higher
   ```

3. **Update pip**:
   ```bash
   pip3 install --upgrade pip
   ```

## Hardware Issues

### GPS HAT Not Detected

**Symptoms:**
- GPS HAT doesn't appear in system
- Serial port not available

**Solutions:**
1. **Check GPIO connections**: Ensure HAT is properly seated
2. **Verify serial port configuration**:
   ```bash
   sudo raspi-config
   # Interface Options > Serial Port
   ```

3. **Check device tree**:
   ```bash
   ls /dev/serial*
   ```

4. **Test serial communication**:
   ```bash
   sudo minicom -D /dev/serial0 -b 9600
   ```

### Display Connection Issues

**Symptoms:**
- Display not detected on I2C
- Connection errors

**Solutions:**
1. **Check JST connections**: Ensure secure connections
2. **Verify Dupont connections**: Check all four wires
3. **Test continuity**: Use multimeter to check connections
4. **Reseat connectors**: Unplug and reconnect all connectors

### Power Issues

**Symptoms:**
- System reboots randomly
- Display flickers
- GPS HAT resets

**Solutions:**
1. **Check power supply**: Use adequate 5V supply (2A+)
2. **Verify connections**: Check all power connections
3. **Test with external supply**: Use bench power supply
4. **Check for shorts**: Inspect all wiring

## Getting Help

If you're still experiencing issues:

1. **Check system logs**:
   ```bash
   sudo journalctl -xe
   ```

2. **Test components individually**:
   - Test GPS with `cgps -s`
   - Test display with simple Python script
   - Test weather API manually

3. **Verify configuration**:
   - Check `config.ini` settings
   - Verify system configuration
   - Test network connectivity

4. **Create issue on GitHub**:
   - Include error messages
   - Provide system information
   - Describe troubleshooting steps taken

## Common Commands Reference

```bash
# Diagnostic Scripts
./i2c-test.sh
./gps-test.sh
./ntp-test.sh

# GPS Status
cgps -s
gpsmon
sudo systemctl status gpsd

# Time Sync Status
chronyc sources
chronyc tracking
timedatectl status

# I2C Detection
sudo i2cdetect -y 1

# Service Management
sudo systemctl status rpi-clock
sudo systemctl restart rpi-clock
sudo journalctl -u rpi-clock -f

# Network Test
ping -c 3 openweathermap.org
curl "http://api.openweathermap.org/data/2.5/weather?zip=90210&appid=YOUR_API_KEY"

# Configuration Validation
python3 /opt/rpi-clock/clock.py --help  # Shows configuration validation errors
```
