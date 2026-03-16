"""Tests for clock.py — weather API resilience, temperature conversion, display logic.

Import strategy: clock.py runs module-level code (config validation, os.chdir,
hardware init) so we must stub hardware imports and redirect the config file read
BEFORE the module runs. Everything after that can be tested by patching module globals.
"""

import configparser as _configparser
import os
import sys
import tempfile
from unittest.mock import MagicMock, Mock, patch

import pytest
import requests

# ── 1. Stub hardware-only imports before clock is loaded ─────────────────────
#    These packages are only available on a Pi; the stubs let tests run anywhere.
for _mod in ("board", "busio", "ntplib"):
    sys.modules.setdefault(_mod, MagicMock())

_ht_mock = MagicMock()
sys.modules.setdefault("adafruit_ht16k33", _ht_mock)
sys.modules.setdefault("adafruit_ht16k33.segments", _ht_mock.segments)

# ── 2. Create a valid config file for the import-time validate_config() call ──
_VALID_CONFIG = """\
[Weather]
api_key = test_api_key_12345678
zip_code = 28801

[Display]
time_format = 12
temp_unit = C
smooth_scroll = false
brightness = 0.8

[NTP]
preferred_server = 127.0.0.1

[Cycle]
time_display = 2
temp_display = 3
feels_like_display = 3
humidity_display = 2

[CustomText]
enabled = false
text =
interval_minutes = 15
display_duration = 3
"""

_tmp_dir = tempfile.mkdtemp()
_config_path = os.path.join(_tmp_dir, "config.ini")
with open(_config_path, "w") as _f:
    _f.write(_VALID_CONFIG)

# ── 3. Import clock with the config redirected to our temp file ───────────────
#    configparser.read() silently ignores missing files, so we redirect
#    /opt/rpi-clock/config.ini → our temp file before the module runs.
_orig_cp_read = _configparser.ConfigParser.read


def _redirect_config_read(self, filenames, encoding=None):
    if isinstance(filenames, str) and "rpi-clock" in filenames:
        return _orig_cp_read(self, _config_path, encoding)
    return _orig_cp_read(self, filenames, encoding)


with (
    patch.object(_configparser.ConfigParser, "read", _redirect_config_read),
    patch("pathlib.Path.exists", return_value=True),
):
    import clock  # noqa: E402


# ── Helpers ───────────────────────────────────────────────────────────────────

_VALID_OWM_RESPONSE = {
    "main": {"temp": 20.0, "feels_like": 18.5, "humidity": 65}
}


def _mock_response(json_data=None, raise_for_status=None):
    """Build a minimal mock requests.Response."""
    resp = Mock()
    resp.json.return_value = json_data if json_data is not None else {}
    if raise_for_status is not None:
        resp.raise_for_status.side_effect = raise_for_status
    else:
        resp.raise_for_status.return_value = None
    return resp


def _http_error(status_code: int) -> requests.exceptions.HTTPError:
    err = requests.exceptions.HTTPError(f"{status_code} Error")
    err.response = Mock(status_code=status_code)
    return err


# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture(autouse=True)
def reset_weather_globals():
    """Give each test a fresh mock Session and known module globals."""
    session = MagicMock()
    clock.SESSION = session
    clock.WEATHER_PARAMS = {"zip": "28801", "appid": "test_key", "units": "metric"}
    clock.TEMP_UNIT = "C"
    yield session


@pytest.fixture(autouse=True)
def no_sleep():
    """Eliminate time.sleep waits in retry loops."""
    with patch("time.sleep"):
        yield


# ── celsius_to_fahrenheit ─────────────────────────────────────────────────────


class TestCelsiusToFahrenheit:
    def test_freezing_point(self):
        assert clock.celsius_to_fahrenheit(0) == 32.0

    def test_boiling_point(self):
        assert clock.celsius_to_fahrenheit(100) == 212.0

    def test_negative_forty_is_equal_in_both_scales(self):
        assert clock.celsius_to_fahrenheit(-40) == -40.0

    def test_body_temperature(self):
        assert abs(clock.celsius_to_fahrenheit(37) - 98.6) < 0.01

    def test_preserves_fractional_precision(self):
        # 22.7°C → 72.86°F; the old bug rounded 22.7→23 first giving 73.4°F
        assert abs(clock.celsius_to_fahrenheit(22.7) - 72.86) < 0.01


# ── build_temp_string ─────────────────────────────────────────────────────────


class TestBuildTempString:
    def test_positive_celsius(self):
        assert clock.build_temp_string(22.7, "C") == "22C"

    def test_negative_celsius(self):
        assert clock.build_temp_string(-5.3, "C") == "-5C"

    def test_zero(self):
        assert clock.build_temp_string(0.0, "C") == "0C"

    def test_positive_fahrenheit(self):
        assert clock.build_temp_string(72.9, "F") == "72F"

    def test_negative_fahrenheit(self):
        assert clock.build_temp_string(-10.0, "F") == "-10F"

    def test_truncates_not_rounds(self):
        # 99.9 truncates to 99, not 100
        assert clock.build_temp_string(99.9, "C") == "99C"


# ── fetch_weather: normal responses ──────────────────────────────────────────


class TestFetchWeatherNormal:
    def test_returns_celsius_tuple(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(_VALID_OWM_RESPONSE)
        assert clock.fetch_weather() == (20.0, 18.5, 65)

    def test_fahrenheit_conversion_preserves_precision(self, reset_weather_globals):
        clock.TEMP_UNIT = "F"
        reset_weather_globals.get.return_value = _mock_response(
            {"main": {"temp": 22.7, "feels_like": 21.0, "humidity": 55}}
        )
        result = clock.fetch_weather()
        assert result is not None
        temp, feels_like, humidity = result
        # 22.7°C → 72.86°F, NOT 73.4°F (the pre-fix int-rounding bug)
        assert abs(temp - 72.86) < 0.01
        assert humidity == 55

    def test_humidity_is_rounded_to_int(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(
            {"main": {"temp": 20.0, "feels_like": 19.0, "humidity": 64.6}}
        )
        result = clock.fetch_weather()
        assert result is not None
        assert result[2] == 65

    def test_extra_api_fields_are_ignored(self, reset_weather_globals):
        """Forward-compat: new OWM fields should not cause failure."""
        reset_weather_globals.get.return_value = _mock_response(
            {
                "main": {
                    "temp": 20.0,
                    "feels_like": 18.5,
                    "humidity": 65,
                    "temp_min": 15.0,
                    "temp_max": 25.0,
                    "new_field_from_future_api_version": "ignored",
                }
            }
        )
        assert clock.fetch_weather() == (20.0, 18.5, 65)

    def test_uses_session_when_available(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(_VALID_OWM_RESPONSE)
        clock.fetch_weather()
        reset_weather_globals.get.assert_called_once()

    def test_falls_back_to_requests_get_when_session_is_none(
        self, reset_weather_globals
    ):
        clock.SESSION = None
        with patch(
            "requests.get", return_value=_mock_response(_VALID_OWM_RESPONSE)
        ) as mock_get:
            result = clock.fetch_weather()
        assert result == (20.0, 18.5, 65)
        mock_get.assert_called_once()


# ── fetch_weather: malformed / unexpected API responses ──────────────────────


class TestFetchWeatherMalformedResponse:
    def test_missing_main_key(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response({"weather": []})
        assert clock.fetch_weather() is None

    def test_empty_json_object(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response({})
        assert clock.fetch_weather() is None

    def test_missing_temp_key(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(
            {"main": {"feels_like": 18.0, "humidity": 60}}
        )
        assert clock.fetch_weather() is None

    def test_null_temp(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(
            {"main": {"temp": None, "feels_like": 18.0, "humidity": 60}}
        )
        assert clock.fetch_weather() is None

    def test_string_temp(self, reset_weather_globals):
        """OWM returning temp as a string instead of a number."""
        reset_weather_globals.get.return_value = _mock_response(
            {"main": {"temp": "warm", "feels_like": "cool", "humidity": 60}}
        )
        assert clock.fetch_weather() is None

    def test_missing_humidity(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(
            {"main": {"temp": 20.0, "feels_like": 18.0}}
        )
        assert clock.fetch_weather() is None

    def test_main_is_a_list_not_dict(self, reset_weather_globals):
        """OWM returns 'main' as an array instead of an object."""
        reset_weather_globals.get.return_value = _mock_response(
            {"main": [20.0, 18.0, 60]}
        )
        assert clock.fetch_weather() is None

    def test_main_is_a_string(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(
            {"main": "unexpected"}
        )
        assert clock.fetch_weather() is None

    def test_temp_is_a_dict(self, reset_weather_globals):
        """Deeply nested unexpected structure."""
        reset_weather_globals.get.return_value = _mock_response(
            {"main": {"temp": {"value": 20.0}, "feels_like": 18.0, "humidity": 60}}
        )
        assert clock.fetch_weather() is None

    def test_no_retry_on_parse_error(self, reset_weather_globals):
        """Malformed responses should not be retried — data won't fix itself."""
        reset_weather_globals.get.return_value = _mock_response({})
        clock.fetch_weather()
        assert reset_weather_globals.get.call_count == 1


# ── fetch_weather: network errors ────────────────────────────────────────────


class TestFetchWeatherNetworkErrors:
    def test_timeout_returns_none_after_retries(self, reset_weather_globals):
        reset_weather_globals.get.side_effect = requests.exceptions.Timeout()
        assert clock.fetch_weather() is None
        assert reset_weather_globals.get.call_count == 3

    def test_connection_error_returns_none_after_retries(self, reset_weather_globals):
        reset_weather_globals.get.side_effect = requests.exceptions.ConnectionError()
        assert clock.fetch_weather() is None
        assert reset_weather_globals.get.call_count == 3

    def test_http_401_returns_none_without_retry(self, reset_weather_globals):
        """Bad API key is a permanent error — no point retrying."""
        reset_weather_globals.get.return_value = _mock_response(
            raise_for_status=_http_error(401)
        )
        assert clock.fetch_weather() is None
        assert reset_weather_globals.get.call_count == 1

    def test_http_404_returns_none_without_retry(self, reset_weather_globals):
        """Bad ZIP code is a permanent error — no point retrying."""
        reset_weather_globals.get.return_value = _mock_response(
            raise_for_status=_http_error(404)
        )
        assert clock.fetch_weather() is None
        assert reset_weather_globals.get.call_count == 1

    def test_http_500_returns_none(self, reset_weather_globals):
        reset_weather_globals.get.return_value = _mock_response(
            raise_for_status=_http_error(500)
        )
        assert clock.fetch_weather() is None

    def test_succeeds_on_second_attempt_after_timeout(self, reset_weather_globals):
        reset_weather_globals.get.side_effect = [
            requests.exceptions.Timeout(),
            _mock_response(_VALID_OWM_RESPONSE),
        ]
        assert clock.fetch_weather() == (20.0, 18.5, 65)
        assert reset_weather_globals.get.call_count == 2

    def test_succeeds_on_third_attempt_after_two_timeouts(self, reset_weather_globals):
        reset_weather_globals.get.side_effect = [
            requests.exceptions.Timeout(),
            requests.exceptions.Timeout(),
            _mock_response(_VALID_OWM_RESPONSE),
        ]
        assert clock.fetch_weather() == (20.0, 18.5, 65)

    def test_four_timeouts_exceeds_retry_limit(self, reset_weather_globals):
        reset_weather_globals.get.side_effect = [
            requests.exceptions.Timeout(),
            requests.exceptions.Timeout(),
            requests.exceptions.Timeout(),
            _mock_response(_VALID_OWM_RESPONSE),  # would succeed but never reached
        ]
        assert clock.fetch_weather() is None
        assert reset_weather_globals.get.call_count == 3
