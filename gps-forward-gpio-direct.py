#!/usr/bin/env python3
"""GPS Forwarding Script for Meshtastic RAK11300 via Direct GPIO

This script forwards GPS NMEA sentences from the Adafruit GPS HAT to the
RAK11300 Meshtastic module via GPIO 17 (Pin 11), which is connected to RAK RX0.

Since Raspberry Pi Zero 2 W only has ONE hardware UART, we use software
serial (bit-banging) to send NMEA data to GPIO 17.

Reference: https://forums.raspberrypi.com/viewtopic.php?t=324183
"""

import subprocess
import sys
import time
import signal
import os

# Try to use RPi.GPIO first, fallback to gpiod
try:
    import RPi.GPIO as GPIO
    GPIO_MODE = 'RPi'
except ImportError:
    try:
        import gpiod
        GPIO_MODE = 'gpiod'
    except ImportError:
        print("✗ No GPIO library available")
        print("  Install one of: python3-rpi.gpio or python3-libgpiod")
        sys.exit(1)

# Configure gpsd to output NMEA, then use gpspipe
# First enable NMEA output via gpsd socket, then pipe NMEA sentences
GPS_PIPE_CMD = ['gpspipe', '-r']  # -r outputs raw NMEA when configured
GPS_GPIO_PIN = 17  # GPIO 17 (Physical Pin 11) - connected to RAK RX0
BAUD_RATE = 9600   # Standard NMEA baud rate
BIT_TIME = 1.0 / BAUD_RATE  # Time per bit in seconds

running = True


def signal_handler(sig, frame):
    """Handle graceful shutdown."""
    global running
    print("\nShutting down GPS forwarder...")
    running = False
    sys.exit(0)


def send_byte_gpiod(pin, byte):
    """Send a byte using gpiod library."""
    chip = gpiod.Chip('gpiochip0')
    line = chip.get_line(pin)
    line.request(consumer='gps-forwarder', type=gpiod.LINE_REQ_DIR_OUT)
    
    try:
        # Start bit (low)
        line.set_value(0)
        time.sleep(BIT_TIME)
        
        # Data bits (LSB first)
        for i in range(8):
            line.set_value((byte >> i) & 1)
            time.sleep(BIT_TIME)
        
        # Stop bit (high)
        line.set_value(1)
        time.sleep(BIT_TIME)
    finally:
        line.release()


def send_byte_rpi(pin, byte):
    """Send a byte using RPi.GPIO library."""
    # Start bit (low)
    GPIO.output(pin, GPIO.LOW)
    time.sleep(BIT_TIME)
    
    # Data bits (LSB first)
    for i in range(8):
        GPIO.output(pin, (byte >> i) & 1)
        time.sleep(BIT_TIME)
    
    # Stop bit (high)
    GPIO.output(pin, GPIO.HIGH)
    time.sleep(BIT_TIME)


def send_string(pin, text):
    """Send a string via software serial."""
    for byte in text.encode('ascii'):
        if GPIO_MODE == 'RPi':
            send_byte_rpi(pin, byte)
        else:
            send_byte_gpiod(pin, byte)


def main():
    """Main GPS forwarding loop."""
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("GPS Forwarder for Meshtastic RAK11300 (Direct GPIO Method)")
    print("=" * 60)
    print(f"Forwarding GPS data from GPS HAT to GPIO {GPS_GPIO_PIN} (Pin 11)")
    print(f"RAK RX0 is connected to GPIO {GPS_GPIO_PIN}")
    print(f"Using {GPIO_MODE} GPIO library")
    print("=" * 60)

    # Setup GPIO pin
    try:
        if GPIO_MODE == 'RPi':
            GPIO.setmode(GPIO.BCM)
            GPIO.setup(GPS_GPIO_PIN, GPIO.OUT, initial=GPIO.HIGH)  # Idle high
            print(f"✓ Configured GPIO {GPS_GPIO_PIN} as output (idle high)")
        else:
            # gpiod will be configured per-operation
            print(f"✓ Will use gpiod for GPIO {GPS_GPIO_PIN}")
    except Exception as e:
        print(f"✗ Failed to configure GPIO: {e}")
        sys.exit(1)

    # Start gpspipe process - it will automatically configure gpsd for NMEA
    # when using -r flag, gpspipe requests NMEA output from gpsd
    try:
        gps_process = subprocess.Popen(
            GPS_PIPE_CMD,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )
        print("✓ Started GPS pipe process")
        print("  Note: gpspipe will configure gpsd for NMEA output automatically")
    except Exception as e:
        print(f"✗ Failed to start GPS pipe: {e}")
        print("  Make sure gpsd is running: sudo systemctl status gpsd")
        if GPIO_MODE == 'RPi':
            GPIO.cleanup()
        sys.exit(1)

    # Forward NMEA sentences
    line_count = 0
    try:
        while running:
            line = gps_process.stdout.readline()
            if not line:
                if gps_process.poll() is not None:
                    print("✗ GPS pipe process ended unexpectedly")
                    break
                continue

            # Only forward NMEA sentences (lines starting with $)
            if line.startswith('$'):
                try:
                    send_string(GPS_GPIO_PIN, line)
                    line_count += 1
                    if line_count % 10 == 0:
                        print(f"Forwarded {line_count} NMEA sentences...")
                except Exception as e:
                    print(f"✗ GPIO write error: {e}")
                    break

    except KeyboardInterrupt:
        pass
    finally:
        print("\nCleaning up...")
        gps_process.terminate()
        gps_process.wait()
        if GPIO_MODE == 'RPi':
            GPIO.cleanup()
        print(f"Forwarded {line_count} NMEA sentences total")
        print("GPS forwarder stopped")


if __name__ == "__main__":
    main()

