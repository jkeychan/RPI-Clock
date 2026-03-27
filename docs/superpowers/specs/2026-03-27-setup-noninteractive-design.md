# Design: Non-Interactive Mode for setup.sh

**Date:** 2026-03-27
**Issue:** jkeychan/rpi-clock#2 — setup.sh hangs when stdin is not a TTY

## Problem

`setup.sh` has two `prompt_yes_no` calls that loop indefinitely when stdin is not a TTY:
- Line 57: "Do you want to continue?" — gates the entire setup
- Line 789: "Do you want to reboot now?" — at the end after hardware config changes

All other steps (apt installs, config writes, systemd wiring) are already non-interactive. Only these two prompts block automated use.

## Goals

- Agents and scripts can run `bash setup.sh` (or `bash setup.sh --reboot`) without hanging
- Humans still get full interactive prompts by default
- Output remains readable for both audiences — non-interactive runs log what they defaulted to

## Flags

| Flag | Effect |
|------|--------|
| `-y`, `--yes`, `--non-interactive` | Skip confirmation prompts; default to yes |
| `--reboot` | Auto-reboot at end if hardware config changes require it |
| `-h`, `--help` | Print usage and exit |

## Auto-detection

If stdin is not a TTY (`[ -t 0 ]` is false), `INTERACTIVE` is set to `false` automatically. This covers `yes | bash setup.sh`, `bash setup.sh < /dev/null`, and SSH invocations without a pseudo-TTY — without requiring callers to know about flags.

`--reboot` is never implied by auto-detection; callers must opt in explicitly.

## Changes to setup.sh

### 1. Flag parsing block (top of script, after color definitions)

```bash
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
```

### 2. `prompt_yes_no` — add non-interactive fast-path

```bash
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

### 3. Reboot block (line ~789) — replace `prompt_yes_no` with `AUTO_REBOOT` check

```bash
if [[ "$AUTO_REBOOT" == "true" ]]; then
    echo "Rebooting in 5 seconds... (--reboot flag set)"
    sleep 5
    sudo reboot
else
    echo ""
    echo -e "${YELLOW}A reboot is required to activate hardware changes (UART, PPS overlay, Bluetooth disable).${NC}"
    echo -e "${WHITE}Run: sudo reboot${NC}"
    echo -e "${CYAN}Tip: re-run setup.sh with --reboot to have this done automatically next time.${NC}"
fi
```

## Scope

No other changes. Package installs, config file writes, systemd wiring, and group membership checks are already non-interactive.

**Total diff:** ~30 lines across 3 locations. No restructuring.

## Example usage

```bash
# Agent / fully automated
bash setup.sh --yes --reboot

# Automated but manual reboot
bash setup.sh --yes

# Piped input (auto-detected as non-interactive, no reboot)
bash setup.sh < /dev/null

# Interactive (default — humans see all prompts)
bash setup.sh
```
