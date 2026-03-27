# Non-Interactive setup.sh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `setup.sh` so it runs without hanging when stdin is not a TTY, and adds `--yes`/`--reboot` flags for agent/script use.

**Architecture:** Add ~20 lines of flag parsing + TTY auto-detection after the root check, add a 3-line fast-path to `prompt_yes_no`, and replace the reboot `prompt_yes_no` call with an `AUTO_REBOOT` flag check. No restructuring; all other script logic is unchanged.

**Tech Stack:** bash, no external dependencies

---

## Files

- **Modify:** `setup.sh` — three targeted changes (flag block, prompt_yes_no, reboot block)
- **Create:** `tests/test_setup_flags.sh` — bash test script for the new behavior

---

### Task 1: Write failing tests

**Files:**
- Create: `tests/test_setup_flags.sh`

- [ ] **Step 1: Create the test file**

```bash
#!/bin/bash
# tests/test_setup_flags.sh
# Tests for non-interactive flag handling in setup.sh
# Run from the repo root: bash tests/test_setup_flags.sh

PASS=0
FAIL=0
SETUP="$(cd "$(dirname "$0")/.." && pwd)/setup.sh"

pass() { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }

# ── Helper: source only the flag-parsing block and prompt_yes_no from setup.sh
# We stub out set -e and skip everything after the function definitions.
load_functions() {
    # Pull out the flag-parsing block and prompt_yes_no, evaluate in a subshell
    # The flag block starts after "# Check if running as root" block (line ~29)
    # and prompt_yes_no is defined at line ~36.
    # We drive this by feeding arguments directly rather than sourcing the whole script.
    true
}

# ── Test 1: --help exits 0 and prints usage
test_help_flag() {
    output=$(bash "$SETUP" --help 2>&1)
    status=$?
    if [[ $status -eq 0 ]] && echo "$output" | grep -q "\-\-reboot"; then
        pass "--help exits 0 and mentions --reboot"
    else
        fail "--help (got status=$status, output='$output')"
    fi
}

# ── Test 2: unknown flag exits 1
test_unknown_flag() {
    output=$(bash "$SETUP" --unknown-flag 2>&1)
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
```

- [ ] **Step 2: Run the tests — expect failures**

```bash
bash tests/test_setup_flags.sh
```

Expected output (tests 1 and 2 fail because setup.sh doesn't have the flags yet; tests 3 and 4 pass because they are self-contained):
```
FAIL: --help exits 0 and mentions --reboot
FAIL: unknown flag exits 1
PASS: prompt_yes_no returns 0 non-interactively without hanging
PASS: prompt_yes_no logs defaulting message

Results: 2 passed, 2 failed
```

---

### Task 2: Add flag parsing and TTY auto-detection to setup.sh

**Files:**
- Modify: `setup.sh` lines 29-34 (insert after root check, before `command_exists`)

- [ ] **Step 1: Insert flag-parsing block**

Find this exact block in `setup.sh` (line 29):
```bash

# Function to check if command exists
command_exists() {
```

Replace with:
```bash

# Non-interactive mode: auto-detect TTY or set via flags
INTERACTIVE=true
AUTO_REBOOT=false

[ -t 0 ] || INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes|--non-interactive) INTERACTIVE=false ;;
        --reboot)                   AUTO_REBOOT=true ;;
        -h|--help)
            echo "Usage: setup.sh [-y|--yes] [--reboot]"
            echo "  -y, --yes     Skip confirmation prompts (non-interactive mode)"
            echo "  --reboot      Auto-reboot at end if hardware config changes require it"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Function to check if command exists
command_exists() {
```

- [ ] **Step 2: Run the tests — expect tests 1 and 2 now pass**

```bash
bash tests/test_setup_flags.sh
```

Expected:
```
PASS: --help exits 0 and mentions --reboot
PASS: unknown flag exits 1
PASS: prompt_yes_no returns 0 non-interactively without hanging
PASS: prompt_yes_no logs defaulting message

Results: 4 passed, 0 failed
```

- [ ] **Step 3: Commit**

```bash
git add setup.sh tests/test_setup_flags.sh
git commit -m "Add non-interactive flag parsing and TTY auto-detection to setup.sh"
```

---

### Task 3: Update prompt_yes_no with non-interactive fast-path

**Files:**
- Modify: `setup.sh` lines 36-45

- [ ] **Step 1: Replace the prompt_yes_no function**

Find this in `setup.sh`:
```bash
# Function to prompt for user input
prompt_yes_no() {
    while true; do
        read -r -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}
```

Replace with:
```bash
# Function to prompt for user input
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
```

- [ ] **Step 2: Verify the existing "continue?" call at line ~57 is unmodified**

Confirm this line is still present unchanged in `setup.sh`:
```bash
if ! prompt_yes_no "Do you want to continue?"; then
```

No change needed here — the updated `prompt_yes_no` handles both cases.

- [ ] **Step 3: Run tests**

```bash
bash tests/test_setup_flags.sh
```

Expected: 4 passed, 0 failed

- [ ] **Step 4: Commit**

```bash
git add setup.sh
git commit -m "Add non-interactive fast-path to prompt_yes_no"
```

---

### Task 4: Replace reboot prompt with AUTO_REBOOT check

**Files:**
- Modify: `setup.sh` lines ~789-802

- [ ] **Step 1: Replace the reboot prompt block**

Find this in `setup.sh`:
```bash
    if prompt_yes_no "Do you want to reboot now to activate all changes?"; then
        echo -e "${YELLOW}Rebooting in 5 seconds...${NC}"
        sleep 5
        sudo reboot
    else
        echo ""
        echo -e "${YELLOW}Manual reboot required:${NC}"
        echo -e "${GREEN}sudo reboot${NC}"
        echo ""
        echo -e "${GREEN}After reboot:${NC}"
        echo -e "${WHITE}-${NC} GPS HAT will be available on ${GREEN}/dev/ttyAMA0${NC}"
        echo -e "${WHITE}-${NC} The 7-segment display should show the current time"
        echo -e "${WHITE}-${NC} If the display is blank, check the troubleshooting guide in ${BLUE}README.md${NC}"
    fi
```

Replace with:
```bash
    if [[ "$AUTO_REBOOT" == "true" ]]; then
        echo -e "${YELLOW}Rebooting in 5 seconds... (--reboot flag set)${NC}"
        sleep 5
        sudo reboot
    else
        echo ""
        echo -e "${YELLOW}A reboot is required to activate hardware changes (UART, PPS overlay, Bluetooth disable).${NC}"
        echo -e "${WHITE}Run:${NC} ${GREEN}sudo reboot${NC}"
        echo ""
        echo -e "${GREEN}After reboot:${NC}"
        echo -e "${WHITE}-${NC} GPS HAT will be available on ${GREEN}/dev/ttyAMA0${NC}"
        echo -e "${WHITE}-${NC} The 7-segment display should show the current time"
        echo -e "${WHITE}-${NC} If the display is blank, check the troubleshooting guide in ${BLUE}README.md${NC}"
        echo ""
        echo -e "${CYAN}Tip: re-run setup.sh with --reboot to reboot automatically next time.${NC}"
    fi
```

- [ ] **Step 2: Run tests**

```bash
bash tests/test_setup_flags.sh
```

Expected: 4 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "Replace reboot prompt with AUTO_REBOOT flag check, add helpful messaging"
```

---

### Task 5: Verify end-to-end non-interactive behavior

- [ ] **Step 1: Confirm `--help` output is complete**

```bash
bash setup.sh --help
```

Expected output:
```
Usage: setup.sh [-y|--yes] [--reboot]
  -y, --yes     Skip confirmation prompts (non-interactive mode)
  --reboot      Auto-reboot at end if hardware config changes require it
```

- [ ] **Step 2: Confirm piped input doesn't hang**

```bash
timeout 5 bash setup.sh < /dev/null 2>&1 | head -10
```

Expected: Script prints the non-interactive defaulting message and proceeds (will fail later on `sudo` commands if not on a Pi, but does NOT hang on the prompt). Exit code will be non-zero due to missing system deps — that's fine.

- [ ] **Step 3: Run full test suite**

```bash
bash tests/test_setup_flags.sh
```

Expected: 4 passed, 0 failed

- [ ] **Step 4: Close the issue**

```bash
gh issue close 2 --comment "Fixed in this commit. Added TTY auto-detection (\`[ -t 0 ]\`), \`-y\`/\`--yes\` flag for non-interactive mode, and \`--reboot\` flag for automated reboots. Piped invocations (\`yes | bash setup.sh\`, \`bash setup.sh < /dev/null\`) no longer hang."
```
