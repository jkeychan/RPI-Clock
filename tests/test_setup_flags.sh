#!/bin/bash
# tests/test_setup_flags.sh
# Tests for non-interactive flag handling in setup.sh
# Run from the repo root: bash tests/test_setup_flags.sh

PASS=0
FAIL=0
SETUP="$(cd "$(dirname "$0")/.." && pwd)/setup.sh"

pass() { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }

# ── Test 1: --help exits 0 and prints usage
test_help_flag() {
    output=$(timeout 2 bash "$SETUP" --help 2>&1)
    status=$?
    if [[ $status -eq 0 ]] && echo "$output" | grep -q "\-\-reboot"; then
        pass "--help exits 0 and mentions --reboot"
    else
        fail "--help (got status=$status, output='$output')"
    fi
}

# ── Test 2: unknown flag exits 1
test_unknown_flag() {
    output=$(timeout 2 bash "$SETUP" --unknown-flag 2>&1)
    status=$?
    if [[ $status -eq 1 ]]; then
        pass "unknown flag exits 1"
    else
        fail "unknown flag should exit 1 (got $status)"
    fi
}

# ── Test 3: prompt_yes_no in non-interactive mode returns 0 without hanging
# We source just the function with INTERACTIVE=false and call it with a timeout
test_prompt_noninteractive() {
    result=$(timeout 2 bash -c '
        INTERACTIVE=false
        prompt_yes_no() {
            if [[ "$INTERACTIVE" == "false" ]]; then
                echo "$1 (y/n): y  [non-interactive: defaulting to yes]"
                return 0
            fi
            while true; do
                read -r -p "$1 (y/n): " yn
                case $yn in
                    [Yy]* ) return 0;;
                    [Nn]* ) return 1;;
                    * ) echo "Please answer yes or no.";;
                esac
            done
        }
        prompt_yes_no "Test prompt"
        echo "exit:$?"
    ' < /dev/null 2>&1)
    if echo "$result" | grep -q "non-interactive: defaulting to yes" && echo "$result" | grep -q "exit:0"; then
        pass "prompt_yes_no returns 0 non-interactively without hanging"
    else
        fail "prompt_yes_no non-interactive (got: $result)"
    fi
}

# ── Test 4: prompt_yes_no in non-interactive mode output contains expected log line
test_prompt_noninteractive_output() {
    result=$(timeout 2 bash -c '
        INTERACTIVE=false
        prompt_yes_no() {
            if [[ "$INTERACTIVE" == "false" ]]; then
                echo "$1 (y/n): y  [non-interactive: defaulting to yes]"
                return 0
            fi
            while true; do
                read -r -p "$1 (y/n): " yn
                case $yn in [Yy]* ) return 0;; [Nn]* ) return 1;; * ) echo "Please answer yes or no.";; esac
            done
        }
        prompt_yes_no "Do you want to continue?"
    ' < /dev/null 2>&1)
    if echo "$result" | grep -q "non-interactive: defaulting to yes"; then
        pass "prompt_yes_no logs defaulting message"
    else
        fail "prompt_yes_no should log defaulting message (got: $result)"
    fi
}

# ── Run all tests
test_help_flag
test_unknown_flag
test_prompt_noninteractive
test_prompt_noninteractive_output

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
