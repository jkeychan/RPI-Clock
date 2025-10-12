"""RPI-Clock: GPS-synchronized timekeeper with weather display.

This module provides a Raspberry Pi-based clock that synchronizes time via GPS
and displays current time, temperature, feels-like temperature, and humidity
on a 7-segment LED display.
"""

import ntplib
import configparser
import requests
import adafruit_ht16k33.segments as segments
import busio
import board
import os
import sys
import time
import signal
from typing import Optional, Tuple, Dict, Any

# Change to /tmp directory to avoid GPIO permission issues
# The lgpio library tries to create notification files in the current working directory
# /opt/rpi-clock has restrictive permissions, so we switch to system temp directory
os.chdir('/tmp')


# Constants - avoid repeated lookups
API_REFRESH_CYCLES: int = 10
API_ENDPOINT: str = "https://api.openweathermap.org/data/2.5/weather"
CONFIG_FILE: str = '/opt/rpi-clock/config.ini'

# Pre-compile regex patterns and cache config values
config: configparser.ConfigParser = configparser.ConfigParser()
config.read_dict({
    'Weather': {'api_key': 'your_api_key_here', 'zip_code': 'your_zip_code_here'},
    'Display': {'time_format': '12', 'temp_unit': 'C', 'smooth_scroll': 'false', 'brightness': '0.8'},
    'NTP': {'preferred_server': '127.0.0.1'},
    'Cycle': {
        'time_display': '2', 'temp_display': '3',
        'feels_like_display': '3', 'humidity_display': '2'
    },
    'CustomText': {
        'enabled': 'false', 'text': '', 'interval_minutes': '15', 'display_duration': '3'
    }
})
config.read(CONFIG_FILE)


def validate_config() -> bool:
    """Validate configuration file and values.

    Returns:
        bool: True if configuration is valid, False otherwise
    """
    errors = []

    # Check if config file exists and was read
    if not os.path.exists(CONFIG_FILE):
        errors.append(f"Configuration file not found: {CONFIG_FILE}")
        return False

    # Validate required sections
    required_sections = ['Weather', 'Display', 'NTP', 'Cycle', 'CustomText']
    for section in required_sections:
        if not config.has_section(section):
            errors.append(f"Missing configuration section: [{section}]")

    # Validate Weather section
    if config.has_section('Weather'):
        if not config.get('Weather', 'api_key', fallback='').strip():
            errors.append(
                "Weather API key is empty - get one from "
                "https://openweathermap.org/api_keys/"
            )
        elif config.get('Weather', 'api_key', fallback='') == \
                'your_openweathermap_api_key_here':
            errors.append(
                "Weather API key not configured - please edit config.ini"
            )

        zip_code = config.get('Weather', 'zip_code', fallback='')
        if not zip_code.strip():
            errors.append("ZIP code is empty - please configure your location")
        elif zip_code == 'your_zip_code_here':
            errors.append("ZIP code not configured - please edit config.ini")
        elif not zip_code.isdigit() or len(zip_code) != 5:
            errors.append("ZIP code must be 5 digits")

    # Validate Display section
    if config.has_section('Display'):
        time_format = config.get('Display', 'time_format', fallback='')
        if time_format not in ['12', '24']:
            errors.append("time_format must be '12' or '24'")

        temp_unit = config.get('Display', 'temp_unit', fallback='')
        if temp_unit not in ['C', 'F']:
            errors.append("temp_unit must be 'C' or 'F'")

        smooth_scroll = config.get('Display', 'smooth_scroll', fallback='')
        if smooth_scroll.lower() not in ['true', 'false']:
            errors.append("smooth_scroll must be 'true' or 'false'")

        brightness = config.get('Display', 'brightness', fallback='')
        try:
            brightness_val = float(brightness)
            if brightness_val < 0.0 or brightness_val > 1.0:
                errors.append("brightness must be between 0.0 and 1.0")
        except (ValueError, TypeError):
            errors.append(
                "brightness must be a valid number between 0.0 and 1.0")

    # Validate Cycle section
    if config.has_section('Cycle'):
        cycle_options = [
            'time_display', 'temp_display',
            'feels_like_display', 'humidity_display'
        ]
        for option in cycle_options:
            try:
                value = config.getint('Cycle', option)
                if value < 1 or value > 60:
                    errors.append(f"{option} must be between 1 and 60 seconds")
            except (ValueError, TypeError):
                errors.append(f"{option} must be a valid integer")

    # Validate CustomText section
    if config.has_section('CustomText'):
        enabled = config.get('CustomText', 'enabled', fallback='')
        if enabled.lower() not in ['true', 'false']:
            errors.append("CustomText enabled must be 'true' or 'false'")
        elif enabled.lower() == 'true':
            custom_text = config.get('CustomText', 'text', fallback='')
            if not custom_text.strip():
                errors.append("CustomText text cannot be empty when enabled")
            elif len(custom_text) > 50:
                errors.append(
                    "CustomText text should be 50 characters or less for optimal display")

            try:
                interval = config.getint('CustomText', 'interval_minutes')
                if interval < 1 or interval > 1440:  # 1 minute to 24 hours
                    errors.append(
                        "CustomText interval_minutes must be between 1 and 1440")
            except (ValueError, TypeError):
                errors.append(
                    "CustomText interval_minutes must be a valid integer")

            try:
                duration = config.getint('CustomText', 'display_duration')
                if duration < 1 or duration > 60:
                    errors.append(
                        "CustomText display_duration must be between 1 and 60 seconds")
            except (ValueError, TypeError):
                errors.append(
                    "CustomText display_duration must be a valid integer")

    # Print errors if any
    if errors:
        print("✗ Configuration validation failed:")
        for error in errors:
            print(f"  - {error}")
        print(f"\nPlease edit {CONFIG_FILE} to fix these issues")
        return False

    print("✓ Configuration validation passed")
    return True


# Validate configuration before proceeding
if not validate_config():
    print("Configuration validation failed - exiting")
    sys.exit(1)

# Cache all config values at startup
API_KEY: str = config['Weather']['api_key']
ZIP_CODE: str = config['Weather']['zip_code']
TIME_FORMAT: str = config['Display']['time_format']
TEMP_UNIT: str = config['Display']['temp_unit']
SMOOTH_SCROLL: bool = config.getboolean('Display', 'smooth_scroll')
BRIGHTNESS: float = config.getfloat('Display', 'brightness')
PREFERRED_NTP_SERVER: str = config['NTP']['preferred_server']
TIME_DISPLAY: int = config.getint('Cycle', 'time_display')
TEMP_DISPLAY: int = config.getint('Cycle', 'temp_display')
FEELS_LIKE_DISPLAY: int = config.getint('Cycle', 'feels_like_display')
HUMIDITY_DISPLAY: int = config.getint('Cycle', 'humidity_display')
CUSTOM_TEXT_ENABLED: bool = config.getboolean('CustomText', 'enabled')
CUSTOM_TEXT: str = config.get('CustomText', 'text', fallback='')
CUSTOM_TEXT_INTERVAL: int = config.getint('CustomText', 'interval_minutes')
CUSTOM_TEXT_DURATION: int = config.getint('CustomText', 'display_duration')

# Pre-compute conversion factor
C_TO_F_FACTOR: float = 9/5  # Avoid repeated division
SCROLL_DELAY: float = 0.12   # Seconds per marquee step for smooth feel

# Global variables
cached_weather_info: Optional[Tuple[int, int, int]] = None
display: Optional[segments.Seg7x4] = None
ntp_client: Optional[ntplib.NTPClient] = None  # Reuse NTP client
SESSION: Optional[requests.Session] = None  # Reusable HTTP session
WEATHER_PARAMS: Optional[Dict[str, str]] = None  # Prebuilt OpenWeather params

# Display write cache
last_display_text: Optional[str] = None
last_time_minute: Optional[int] = None
last_custom_text_time: Optional[float] = None


def signal_handler(sig: int, frame: Any) -> None:
    """Handle graceful shutdown on SIGINT (Ctrl+C) or SIGTERM.

    Args:
        sig: Signal number
        frame: Current stack frame
    """
    if display:
        display.fill(0)
        display.show()
    sys.exit(0)


def initialize_display() -> bool:
    """Initialize the 7-segment display with error handling.

    Returns:
        bool: True if display initialized successfully, False otherwise
    """
    global display
    try:
        i2c = busio.I2C(board.SCL, board.SDA)
        display = segments.Seg7x4(i2c)
        display.brightness = BRIGHTNESS
        print(
            f"✓ 7-segment display initialized successfully (brightness: {BRIGHTNESS})")
        return True
    except busio.I2CError as e:
        print(f"✗ I2C communication error: {e}")
        print("  Check I2C connections and enable I2C interface")
        return False
    except ValueError as e:
        print(f"✗ Display address error: {e}")
        print("  Check display I2C address (should be 0x70)")
        return False
    except Exception as e:
        print(f"✗ Display initialization failed: {e}")
        print("  Run i2c-test.sh for detailed diagnostics")
        return False


def initialize_ntp() -> bool:
    """Initialize NTP client once.

    Returns:
        bool: True if NTP client initialized successfully, False otherwise
    """
    global ntp_client
    try:
        ntp_client = ntplib.NTPClient()
        print("✓ NTP client initialized successfully")
        return True
    except Exception as e:
        print(f"✗ NTP client initialization failed: {e}")
        print("  NTP functionality will be limited")
        return False


def initialize_http_session() -> bool:
    """Initialize a reusable HTTP session and prebuild request params.

    Returns:
        bool: True if HTTP session initialized successfully, False otherwise
    """
    global SESSION, WEATHER_PARAMS
    try:
        SESSION = requests.Session()
        WEATHER_PARAMS = {
            "zip": ZIP_CODE, "appid": API_KEY, "units": "metric"
        }
        print("✓ HTTP session initialized successfully")
        return True
    except Exception as e:
        print(f"✗ HTTP session initialization failed: {e}")
        print("  Weather functionality will be limited")
        SESSION = None
        WEATHER_PARAMS = None
        return False


def celsius_to_fahrenheit(celsius: float) -> float:
    """Convert Celsius temperature to Fahrenheit - optimized.

    Args:
        celsius: Temperature in Celsius

    Returns:
        float: Temperature in Fahrenheit
    """
    return (celsius * C_TO_F_FACTOR) + 32


def write_display(text: str) -> None:
    """Write text to display only if it changed.

    Args:
        text: Text to display on the 7-segment display
    """
    global last_display_text
    if not display:
        return
    if text != last_display_text:
        display.print(text)
        display.show()
        last_display_text = text


def build_temp_string(temp: float, unit: str) -> str:
    """Create temperature string without truncation for scrolling.

    Args:
        temp: Temperature value
        unit: Temperature unit (C or F)

    Returns:
        str: Formatted temperature string
    """
    if temp < 0:
        return f"-{int(abs(temp))}{unit}"
    return f"{int(temp)}{unit}"


def display_temperature(temp: float, unit: str) -> None:
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


def display_time() -> None:
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


def display_humidity(humidity: float) -> None:
    """Display humidity with integer rounding.

    Args:
        humidity: Humidity percentage value
    """
    if not display:
        return

    # Show humidity with "rH" prefix (e.g., "rH50" for 50% humidity)
    # Since 7-segment display can't show '%', we use "rH" to indicate relative humidity
    write_display(f"rH{int(round(humidity)):02d}")


def scroll_combined_label_value(
    label: str, value_text: str, delay: float = SCROLL_DELAY
) -> None:
    """Scroll a combined label and value across the display.

    Example: label='Out', value_text='72F' => 'Out 72F   ' scrolls once.

    Args:
        label: Label text to display
        value_text: Value text to display
        delay: Delay between scroll steps in seconds
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


def fetch_weather() -> Optional[Tuple[int, int, int]]:
    """Fetch weather with optimized retry logic.

    Returns:
        Optional[Tuple[int, int, int]]: (temperature, feels_like, humidity) or None
    """
    max_retries = 3
    retry_delay = 5

    # Use prebuilt params and session
    params = WEATHER_PARAMS

    for attempt in range(max_retries):
        try:
            if SESSION is None:
                response = requests.get(
                    API_ENDPOINT, params=params, timeout=10)
            else:
                response = SESSION.get(
                    API_ENDPOINT, params=params, timeout=10)
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

        except requests.exceptions.Timeout:
            print(
                f"✗ Weather API timeout (attempt {attempt + 1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                print("  Weather data unavailable - check internet connection")
                return None
        except requests.exceptions.ConnectionError:
            print(
                f"✗ Weather API connection error "
                f"(attempt {attempt + 1}/{max_retries})"
            )
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                print("  Weather data unavailable - check internet connection")
                return None
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 401:
                print("✗ Weather API authentication failed - check API key")
            elif e.response.status_code == 404:
                print("✗ Weather API location not found - check ZIP code")
            else:
                print(f"✗ Weather API HTTP error: {e}")
            return None
        except requests.exceptions.RequestException as e:
            print(f"✗ Weather API request error: {e}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                return None
        except (KeyError, ValueError, TypeError) as e:
            print(f"✗ Weather data parsing error: {e}")
            print("  Weather API response format may have changed")
            return None


def get_current_time() -> time.struct_time:
    """Get current time with cached NTP client.

    Returns:
        time.struct_time: Current time structure
    """
    try:
        if ntp_client:
            response = ntp_client.request(
                PREFERRED_NTP_SERVER, version=3, timeout=5)
            return time.localtime(response.tx_time)
    except ntplib.NTPException as e:
        print(f"✗ NTP synchronization failed: {e}")
        print("  Using system time - check GPS/NTP configuration")
    except Exception as e:
        print(f"✗ Time synchronization error: {e}")
    return time.localtime()


def display_metric_with_message(
    message: str, display_function: Any, *args: Any, delay: int = 2
) -> None:
    """Display metric with optimized timing.

    Args:
        message: Message to display via marquee
        display_function: Function to call after message
        *args: Arguments to pass to display_function
        delay: Delay in seconds after message
    """
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


def display_custom_text() -> None:
    """Display custom text with scrolling animation.

    Uses the configured custom text and scrolls it across the display
    for the configured duration.
    """
    if not display or not CUSTOM_TEXT_ENABLED or not CUSTOM_TEXT.strip():
        return

    print(f"Displaying custom text: {CUSTOM_TEXT}")

    # Clear display and scroll the custom text
    display.fill(0)
    display.marquee(CUSTOM_TEXT, delay=SCROLL_DELAY, loop=False)

    # Wait for the configured duration
    time.sleep(CUSTOM_TEXT_DURATION)

    # Invalidate cache since marquee wrote directly to display
    global last_display_text
    last_display_text = None


def should_display_custom_text() -> bool:
    """Check if custom text should be displayed based on interval timing.

    Returns:
        bool: True if custom text should be displayed, False otherwise
    """
    if not CUSTOM_TEXT_ENABLED or not CUSTOM_TEXT.strip():
        return False

    global last_custom_text_time
    current_time = time.time()

    # If never displayed before, display it
    if last_custom_text_time is None:
        last_custom_text_time = current_time
        return True

    # Check if enough time has passed
    time_since_last = current_time - last_custom_text_time
    interval_seconds = CUSTOM_TEXT_INTERVAL * 60

    if time_since_last >= interval_seconds:
        last_custom_text_time = current_time
        return True

    return False


def main_loop() -> None:
    """Optimized main loop with reduced function calls."""
    cycle_counter = 0
    global cached_weather_info

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

            # Check if custom text should be displayed
            if should_display_custom_text():
                display_custom_text()

            # Weather display - only fetch when needed
            if cycle_counter == 0 or cached_weather_info is None:
                cached_weather_info = fetch_weather()

            if cached_weather_info:
                temperature, feels_like, humidity = cached_weather_info

                if SMOOTH_SCROLL:
                    # Scroll label + value together for a ticker feel
                    scroll_combined_label_value(
                        'Out', build_temp_string(temperature, TEMP_UNIT)
                    )
                    scroll_combined_label_value(
                        'FEEL', build_temp_string(feels_like, TEMP_UNIT)
                    )
                    scroll_combined_label_value(
                        'rH', f"{int(round(humidity)):02d}")
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

        except KeyboardInterrupt:
            print("\nReceived interrupt signal - shutting down gracefully")
            break
        except Exception as e:
            print(f"✗ Unexpected error in main loop: {e}")
            print("  Continuing operation - check system logs for details")
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
