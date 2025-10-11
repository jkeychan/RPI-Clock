import os
import sys
import time
import signal

# Change to home directory to avoid GPIO permission issues
# The lgpio library tries to create notification files in the current working directory
# /opt/rpi-clock has restrictive permissions, so we switch to home directory
os.chdir(os.path.expanduser('~'))

import board
import busio
import adafruit_ht16k33.segments as segments
import requests
import configparser
import ntplib

# Constants - avoid repeated lookups
API_REFRESH_CYCLES = 10
api_endpoint = "https://api.openweathermap.org/data/2.5/weather"
CONFIG_FILE = '/opt/rpi-clock/config.ini'

# Pre-compile regex patterns and cache config values
config = configparser.ConfigParser()
config.read_dict({
    'Weather': {'API_KEY': 'your_api_key_here', 'ZIP_CODE': 'your_zip_code_here'},
    'Display': {'TIME_FORMAT': '12', 'TEMP_UNIT': 'C'},
    'NTP': {'PREFERRED_SERVER': '127.0.0.1'},
    'Cycle': {'time_display': '2', 'temp_display': '3', 'feels_like_display': '3', 'humidity_display': '2'}
})
config.read(CONFIG_FILE)

# Cache all config values at startup
API_KEY = config['Weather']['API_KEY']
ZIP_CODE = config['Weather']['ZIP_CODE']
TIME_FORMAT = config['Display']['TIME_FORMAT']
TEMP_UNIT = config['Display']['TEMP_UNIT']
PREFERRED_NTP_SERVER = config['NTP']['PREFERRED_SERVER']
TIME_DISPLAY = config.getint('Cycle', 'time_display')
TEMP_DISPLAY = config.getint('Cycle', 'temp_display')
FEELS_LIKE_DISPLAY = config.getint('Cycle', 'feels_like_display')
HUMIDITY_DISPLAY = config.getint('Cycle', 'humidity_display')

# Pre-compute conversion factor
C_TO_F_FACTOR = 9/5  # Avoid repeated division
SMOOTH_SCROLL = True  # Enable stock-ticker style scrolling for metrics
SCROLL_DELAY = 0.12   # Seconds per marquee step for smooth feel

# Global variables
cached_weather_info = None
display = None
ntp_client = None  # Reuse NTP client
SESSION = None  # Reusable HTTP session
WEATHER_PARAMS = None  # Prebuilt OpenWeather params

# Display write cache
last_display_text = None
last_time_minute = None


def signal_handler(sig, frame):
    """Handle graceful shutdown on SIGINT (Ctrl+C) or SIGTERM."""
    if display:
        display.fill(0)
        display.show()
    sys.exit(0)


def initialize_display():
    """Initialize the 7-segment display with error handling."""
    global display
    try:
        i2c = busio.I2C(board.SCL, board.SDA)
        display = segments.Seg7x4(i2c)
        return True
    except Exception as e:
        print(f"Display initialization failed: {e}")
        return False


def initialize_ntp():
    """Initialize NTP client once."""
    global ntp_client
    try:
        ntp_client = ntplib.NTPClient()
        return True
    except Exception as e:
        print(f"NTP client initialization failed: {e}")
        return False


def initialize_http_session():
    """Initialize a reusable HTTP session and prebuild request params."""
    global SESSION, WEATHER_PARAMS
    try:
        SESSION = requests.Session()
        WEATHER_PARAMS = {"zip": ZIP_CODE, "appid": API_KEY, "units": "metric"}
        return True
    except Exception as e:
        print(f"HTTP session initialization failed: {e}")
        SESSION = None
        WEATHER_PARAMS = None
        return False


def celsius_to_fahrenheit(celsius):
    """Convert Celsius temperature to Fahrenheit - optimized."""
    return (celsius * C_TO_F_FACTOR) + 32


def write_display(text):
    """Write text to display only if it changed."""
    global last_display_text
    if not display:
        return
    if text != last_display_text:
        display.print(text)
        display.show()
        last_display_text = text


def build_temp_string(temp, unit):
    """Create temperature string without truncation for scrolling."""
    if temp < 0:
        return f"-{int(abs(temp))}{unit}"
    return f"{int(temp)}{unit}"


def display_temperature(temp, unit):
    """Display temperature with minimal string operations."""
    if not display:
        return

    # Use integer formatting for better performance
    if temp < 0:
        temp_str = f"-{int(abs(temp))}{unit}"
    else:
        temp_str = f"{int(temp)}{unit}"

    # Truncate and pad in one operation
    write_display(temp_str[:4].rjust(4))


def display_time():
    """Display time with optimized formatting."""
    if not display:
        return

    now = time.localtime()
    hour = now.tm_hour
    if TIME_FORMAT == '12':
        hour = hour % 12 or 12  # More efficient than if/else
    minute = now.tm_min

    # Use format string for better performance
    write_display(f"{hour:2d}{minute:02d}")


def display_humidity(humidity):
    """Display humidity with integer rounding."""
    if not display:
        return

    # Show percentage in static mode (omit label to fit 4 chars)
    write_display(f"{int(round(humidity)):02d}%".rjust(4))


def scroll_combined_label_value(label, value_text, delay=SCROLL_DELAY):
    """Scroll a combined label and value across the display.

    Example: label='Out', value_text='72F' => 'Out 72F   ' scrolls once.
    """
    if not display:
        return
    # Compose with padding at end to allow scroll-off
    full_text = f"{label} {value_text}   "
    display.fill(0)
    display.marquee(full_text, delay=delay, loop=False)
    # Invalidate cache since marquee wrote directly to display
    global last_display_text
    last_display_text = None


def fetch_weather():
    """Fetch weather with optimized retry logic."""
    max_retries = 3
    retry_delay = 5

    # Use prebuilt params and session
    params = WEATHER_PARAMS

    for attempt in range(max_retries):
        try:
            if SESSION is None:
                response = requests.get(
                    api_endpoint, params=params, timeout=10)
            else:
                response = SESSION.get(api_endpoint, params=params, timeout=10)
            response.raise_for_status()
            weather_data = response.json()

            # Extract data once
            main_data = weather_data["main"]
            temperature = int(round(main_data["temp"]))
            feels_like = int(round(main_data["feels_like"]))
            humidity = int(round(main_data["humidity"]))

            # Convert units if needed
            if TEMP_UNIT == 'F':
                temperature = celsius_to_fahrenheit(temperature)
                feels_like = celsius_to_fahrenheit(feels_like)

            return temperature, feels_like, humidity

        except requests.exceptions.RequestException as e:
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                return None


def get_current_time():
    """Get current time with cached NTP client."""
    try:
        if ntp_client:
            response = ntp_client.request(
                PREFERRED_NTP_SERVER, version=3, timeout=5)
            return time.localtime(response.tx_time)
    except Exception:
        pass
    return time.localtime()


def display_metric_with_message(message, display_function, *args, delay=2):
    """Display metric with optimized timing."""
    if not display:
        return

    display.fill(0)
    display.marquee(message, delay=0.2, loop=False)
    time.sleep(delay)
    # Marquee changed the display buffer; invalidate cache so next write isn't skipped
    global last_display_text
    last_display_text = None
    display_function(*args)
    # display.show() occurs within write_display when content changes


def main_loop():
    """Optimized main loop with reduced function calls."""
    cycle_counter = 0

    while True:
        try:
            # Time display loop - optimized with monotonic tick and cached redraws
            total_seconds = TIME_DISPLAY * 2  # preserve original semantics
            if display:
                # Initial render and minute cache
                now_struct = time.localtime()
                global last_time_minute
                last_time_minute = now_struct.tm_min
                display_time()

                seconds_elapsed = 0
                colon_on = False
                next_tick = time.monotonic()
                while seconds_elapsed < total_seconds:
                    colon_on = not colon_on
                    display.colon = colon_on
                    display.show()

                    # Update time at minute change without redrawing otherwise
                    now_struct = time.localtime()
                    if now_struct.tm_min != last_time_minute:
                        last_time_minute = now_struct.tm_min
                        display_time()

                    next_tick += 1.0
                    sleep_duration = next_tick - time.monotonic()
                    if sleep_duration > 0:
                        time.sleep(sleep_duration)
                    seconds_elapsed += 1
            else:
                time.sleep(total_seconds)

            # Weather display - only fetch when needed
            if cycle_counter == 0 or cached_weather_info is None:
                cached_weather_info = fetch_weather()

            if cached_weather_info:
                temperature, feels_like, humidity = cached_weather_info

                if SMOOTH_SCROLL:
                    # Scroll label + value together for a ticker feel
                    scroll_combined_label_value(
                        'Out', build_temp_string(temperature, TEMP_UNIT))
                    scroll_combined_label_value(
                        'FEEL', build_temp_string(feels_like, TEMP_UNIT))
                    scroll_combined_label_value(
                        'rH', f"{int(round(humidity)):02d}%")
                else:
                    # Original stepwise messaging
                    display_metric_with_message(
                        'Out', display_temperature, temperature, TEMP_UNIT)
                    time.sleep(TEMP_DISPLAY)
                    display_metric_with_message(
                        'feel', display_temperature, feels_like, TEMP_UNIT)
                    time.sleep(FEELS_LIKE_DISPLAY)
                    display_humidity(humidity)
                    time.sleep(HUMIDITY_DISPLAY)

            cycle_counter = (cycle_counter + 1) % API_REFRESH_CYCLES

        except Exception as e:
            print(f"Error in main loop: {e}")
            time.sleep(5)


if __name__ == "__main__":
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Initialize components
    initialize_display()
    initialize_ntp()
    initialize_http_session()

    print("Starting Raspberry Pi Clock...")
    main_loop()
