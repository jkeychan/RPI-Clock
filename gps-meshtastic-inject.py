#!/usr/bin/env python3
"""GPS position injector for Meshtastic RAK11310.

Reads GPS fix from gpsd and injects position into the Meshtastic
radio via the Python API over USB (/dev/ttyACM0), replacing the
unreliable GPIO bit-bang approach.

Requires:
  - gpsd running with GPS HAT on /dev/ttyAMA0
  - meshtastic Python library (installed in /opt/rpi-clock/venv)
  - RAK11310 connected via USB on /dev/ttyACM0
"""

import json
import subprocess
import sys
import time
import signal
import types
from typing import Any, Optional

MESHTASTIC_PORT = "/dev/ttyACM0"
MIN_FIX_MODE = 2  # 2=2D fix minimum, 3=3D
UPDATE_INTERVAL = 120  # seconds between position pushes
RETRY_DELAY = 15  # seconds to wait before reconnect attempt

running = True
iface = None


def signal_handler(sig: int, frame: Optional[types.FrameType]) -> None:
    global running
    running = False
    sys.exit(0)


def connect_radio() -> Optional[Any]:
    import meshtastic.serial_interface

    try:
        radio = meshtastic.serial_interface.SerialInterface(MESHTASTIC_PORT)
        print(f"✓ Connected to Meshtastic radio on {MESHTASTIC_PORT}")
        return radio
    except Exception as e:
        print(f"✗ Failed to connect to radio: {e}")
        return None


def inject_position(radio: Any, lat: float, lon: float, alt: float) -> bool:
    try:
        radio.localNode.setFixedPosition(lat, lon, int(alt))
        print(f"✓ Position injected: {lat:.6f}, {lon:.6f}, " f"alt={int(alt)}m MSL")
        return True
    except Exception as e:
        print(f"✗ Failed to inject position: {e}")
        return False


def main() -> None:
    global iface

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("Meshtastic GPS Position Injector")
    print("=" * 60)
    print(f"GPS source : gpsd (/dev/ttyAMA0 via gpspipe)")
    print(f"Meshtastic : {MESHTASTIC_PORT}")
    print(f"Update rate: every {UPDATE_INTERVAL}s when fix is valid")
    print("=" * 60)

    try:
        proc = subprocess.Popen(
            ["gpspipe", "-w"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        print("✓ gpsd listener started")
    except Exception as e:
        print(f"✗ Failed to start gpspipe: {e}")
        print("  Is gpsd running?  sudo systemctl status gpsd")
        sys.exit(1)

    assert proc.stdout is not None

    last_update: float = 0
    updates_sent: int = 0
    waiting_for_fix: bool = True

    while running:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None:
                print("✗ gpspipe process ended unexpectedly")
                break
            continue

        try:
            msg = json.loads(line.strip())
        except json.JSONDecodeError:
            continue

        if msg.get("class") != "TPV":
            continue

        mode = msg.get("mode", 0)
        lat = msg.get("lat")
        lon = msg.get("lon")
        alt = float(msg.get("altMSL", msg.get("alt", 0.0)))

        if mode < MIN_FIX_MODE or lat is None or lon is None:
            if not waiting_for_fix:
                print("⚠  GPS fix lost — waiting...")
                waiting_for_fix = True
            continue

        if waiting_for_fix:
            fix_type = "2D" if mode == 2 else "3D"
            print(f"✓ GPS {fix_type} fix acquired: {lat:.6f}, {lon:.6f}")
            waiting_for_fix = False

        now = time.monotonic()
        if now - last_update < UPDATE_INTERVAL:
            continue

        # Connect or reconnect to radio
        if iface is None:
            iface = connect_radio()
            if iface is None:
                time.sleep(RETRY_DELAY)
                continue

        if inject_position(iface, lat, lon, alt):
            updates_sent += 1
            last_update = now
        else:
            # Stale connection — drop it and reconnect next cycle
            try:
                iface.close()
            except Exception:
                pass
            iface = None

    proc.terminate()
    proc.wait()
    if iface:
        try:
            iface.close()
        except Exception:
            pass
    print(f"GPS injector stopped. Total updates sent: {updates_sent}")


if __name__ == "__main__":
    main()
