#!/usr/bin/env bash
set -e

# ==============================================================================
# CLI DIARY UNINSTALLER
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${RED}${BOLD}CLI Diary Uninstaller${RESET}"
echo "----------------------------------------"

prompt_confirm() {
    local prompt_msg="$1"
    local default_yn="$2" # "y" or "n"
    local user_val=""

    if [ -t 0 ]; then
        read -r -p "$prompt_msg" user_val
    elif [ -e /dev/tty ]; then
        read -r -p "$prompt_msg" user_val < /dev/tty
    fi

    user_val=$(echo "$user_val" | tr '[:upper:]' '[:lower:]')

    if [ -z "$user_val" ]; then
        user_val="$default_yn"
    fi

    if [[ "$user_val" == "y"* ]]; then
        return 0
    else
        return 1
    fi
}

# Load config to find diary directory
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/diary"
CONFIG_FILE="$CONFIG_DIR/config"
DIARY_DIR_SAVED=""

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    DIARY_DIR_SAVED="$DIARY_DIR"
fi

# 1. Remove executable binary
BIN_PATHS=(
    "${PREFIX:-}/bin/diary"
    "$HOME/.local/bin/diary"
    "/usr/local/bin/diary"
)

REMOVED_BIN=false

for bpath in "${BIN_PATHS[@]}"; do
    if [ -n "$bpath" ] && [ -f "$bpath" ]; then
        rm -f "$bpath"
        echo -e "Removed binary: ${GREEN}$bpath${RESET}"
        REMOVED_BIN=true
    fi
done

if command -v diary >/dev/null 2>&1; then
    RESOLVED_BIN=$(command -v diary)
    rm -f "$RESOLVED_BIN" 2>/dev/null || true
    echo -e "Removed binary: ${GREEN}$RESOLVED_BIN${RESET}"
    REMOVED_BIN=true
fi

if [ "$REMOVED_BIN" = false ]; then
    echo "No installed 'diary' binary found in standard PATH locations."
fi

# 2. Remove configuration
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo -e "Removed configuration: ${GREEN}$CONFIG_DIR${RESET}"
fi

# 3. Optional note directory removal
if [ -n "$DIARY_DIR_SAVED" ] && [ -d "$DIARY_DIR_SAVED" ]; then
    echo
    if prompt_confirm "Do you also want to permanently delete your diary notes directory ($DIARY_DIR_SAVED)? [y/N]: " "n"; then
        rm -rf "$DIARY_DIR_SAVED"
        echo -e "${RED}Deleted notes directory: $DIARY_DIR_SAVED${RESET}"
    else
        echo -e "Kept notes directory intact at: ${GREEN}$DIARY_DIR_SAVED${RESET}"
    fi
fi

echo
echo -e "${GREEN}${BOLD}CLI Diary has been uninstalled.${RESET}"
