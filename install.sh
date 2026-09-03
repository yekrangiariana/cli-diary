#!/usr/bin/env bash
set -e

# ==============================================================================
# CLI DIARY INSTALLER
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${BLUE}"
echo "  ____ _     ___   ____  _                  "
echo " / ___| |   |_ _| |  _ \(_) __ _ _ __ _   _ "
echo "| |   | |    | |  | | | | |/ _\` | '__| | | |"
echo "| |___| |___ | |  | |_| | | (_| | |  | |_| |"
echo " \____|_____|___| |____/|_|\__,_|_|   \__, |"
echo "                                      |___/ "
echo -e "${RESET}"
echo -e "${BOLD}CLI Diary Automated Installer${RESET}"
echo "----------------------------------------"

# 1. OS Detection
IS_TERMUX=false
IS_MACOS=false
IS_LINUX=false

if [ -d "/data/data/com.termux" ] || [ -n "$TERMUX_VERSION" ]; then
    IS_TERMUX=true
    OS_NAME="Android (Termux)"
elif [ "$(uname -s)" = "Darwin" ]; then
    IS_MACOS=true
    OS_NAME="macOS"
else
    IS_LINUX=true
    OS_NAME="Linux"
fi

echo -e "Detected OS: ${GREEN}$OS_NAME${RESET}"

# Interactive helper for reading input (handles piped curl | bash)
prompt_input() {
    local prompt_msg="$1"
    local default_val="$2"
    local user_val=""

    if [ -t 0 ]; then
        read -r -p "$prompt_msg" user_val
    elif [ -e /dev/tty ]; then
        read -r -p "$prompt_msg" user_val < /dev/tty
    fi

    if [ -z "$user_val" ]; then
        echo "$default_val"
    else
        echo "$user_val"
    fi
}

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

# 2. Dependency Checking
echo
echo -e "${BOLD}Checking dependencies...${RESET}"

MISSING_DEPS=()

for cmd in git fzf awk sed find; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ Core dependencies installed (git, fzf, core utilities).${RESET}"
else
    echo -e "${YELLOW}Missing dependencies: ${MISSING_DEPS[*]}${RESET}"
    
    if [ "$IS_TERMUX" = true ]; then
        if prompt_confirm "Would you like to install missing dependencies via pkg? [Y/n]: " "y"; then
            echo "Installing packages..."
            pkg update < /dev/tty && pkg install -y git fzf termux-api coreutils findutils gawk sed nano < /dev/tty
        fi
    elif [ "$IS_MACOS" = true ]; then
        if command -v brew >/dev/null 2>&1; then
            if prompt_confirm "Would you like to install missing dependencies via Homebrew? [Y/n]: " "y"; then
                echo "Installing packages via Homebrew..."
                brew install git fzf < /dev/tty
            fi
        else
            echo "Homebrew is not installed. Please install ${MISSING_DEPS[*]} manually using your package manager."
        fi
    elif [ "$IS_LINUX" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            if prompt_confirm "Would you like to install missing dependencies via apt? [Y/n]: " "y"; then
                sudo apt-get update < /dev/tty && sudo apt-get install -y git fzf nano < /dev/tty
            fi
        elif command -v pacman >/dev/null 2>&1; then
            if prompt_confirm "Would you like to install missing dependencies via pacman? [Y/n]: " "y"; then
                sudo pacman -Sy --noconfirm git fzf nano < /dev/tty
            fi
        elif command -v dnf >/dev/null 2>&1; then
            if prompt_confirm "Would you like to install missing dependencies via dnf? [Y/n]: " "y"; then
                sudo dnf install -y git fzf nano < /dev/tty
            fi
        else
            echo "Please install missing dependencies (${MISSING_DEPS[*]}) using your distribution's package manager."
        fi
    fi
fi

# 3. Diary Storage Path & Git Repository Setup
echo
echo -e "${BOLD}Configuring Diary Storage Path${RESET}"

if [ "$IS_TERMUX" = true ]; then
    DEFAULT_DIR="$HOME/storage/shared/Documents/Diary"
    if [ ! -d "$HOME/storage" ]; then
        echo "Setting up Termux storage access..."
        termux-setup-storage || true
    fi
else
    DEFAULT_DIR="$HOME/Documents/Diary"
fi

CHOSEN_DIR=$(prompt_input "Enter directory to save diary entries [$DEFAULT_DIR]: " "$DEFAULT_DIR")
CHOSEN_DIR="${CHOSEN_DIR/#\~/$HOME}"

CLONED_REPO=false

if prompt_confirm "Do you already have an existing GitHub repository for your diary notes? [y/N]: " "n"; then
    REMOTE_URL=$(prompt_input "Enter your GitHub repository URL (e.g. https://github.com/user/notes.git): " "")
    if [ -n "$REMOTE_URL" ]; then
        if [ -d "$CHOSEN_DIR" ] && [ "$(ls -A "$CHOSEN_DIR" 2>/dev/null)" ]; then
            echo -e "${YELLOW}Notice: $CHOSEN_DIR is not empty. Linking remote origin instead of cloning.${RESET}"
        else
            echo "Cloning repository from $REMOTE_URL..."
            git clone "$REMOTE_URL" "$CHOSEN_DIR" < /dev/tty || true
            CLONED_REPO=true
        fi
    fi
fi

mkdir -p "$CHOSEN_DIR" 2>/dev/null || true
echo -e "Diary directory set to: ${GREEN}$CHOSEN_DIR${RESET}"

# 4. Preferred Editor Prompt
echo
echo -e "${BOLD}Configuring Text Editor${RESET}"
DEFAULT_EDITOR="${DIARY_EDITOR:-${EDITOR:-nano}}"
echo "Supported options include any editor command (e.g. nano, nvim, vim, micro, hx, 'code --wait')."
CHOSEN_EDITOR=$(prompt_input "Preferred text editor command [$DEFAULT_EDITOR]: " "$DEFAULT_EDITOR")

# 5. Save Configuration
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/diary"
CONFIG_FILE="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
# CLI Diary Configuration
DIARY_DIR="$CHOSEN_DIR"
DIARY_EDITOR="$CHOSEN_EDITOR"
EOF

echo -e "Saved configuration to: ${GREEN}$CONFIG_FILE${RESET}"

# 6. Binary Installation Target
echo
echo -e "${BOLD}Installing executable...${RESET}"

if [ "$IS_TERMUX" = true ]; then
    TARGET_BIN_DIR="${PREFIX}/bin"
else
    TARGET_BIN_DIR="$HOME/.local/bin"
fi

mkdir -p "$TARGET_BIN_DIR"

# Download or copy diary.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
TARGET_EXEC="$TARGET_BIN_DIR/diary"

if [ -f "$SCRIPT_DIR/diary.sh" ]; then
    cp "$SCRIPT_DIR/diary.sh" "$TARGET_EXEC"
else
    echo "Fetching diary.sh from GitHub..."
    curl -fsSL "https://raw.githubusercontent.com/yekrangiariana/cli-diary/main/diary.sh" -o "$TARGET_EXEC"
fi

chmod +x "$TARGET_EXEC"
echo -e "Installed binary to: ${GREEN}$TARGET_EXEC${RESET}"

# 7. Git Repository & Remote Link Setup
echo
if [ "$CLONED_REPO" = true ]; then
    echo -e "${GREEN}✓ Git repository cloned and ready in $CHOSEN_DIR${RESET}"
    if [ "$IS_TERMUX" = true ] || [[ "$CHOSEN_DIR" == *"storage/shared"* ]]; then
        git -C "$CHOSEN_DIR" config core.fileMode false
        echo -e "${GREEN}✓ Configured core.fileMode = false for Android shared storage.${RESET}"
    fi
else
    if prompt_confirm "Would you like to initialize Git and link a remote GitHub repository? [Y/n]: " "y"; then
        if ! git -C "$CHOSEN_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git -C "$CHOSEN_DIR" init >/dev/null
            echo -e "${GREEN}✓ Git repository initialized in $CHOSEN_DIR${RESET}"
        else
            echo -e "${GREEN}✓ $CHOSEN_DIR is already a Git repository.${RESET}"
        fi

        # Fix permission/mode tracking issue on Termux / Android shared storage
        if [ "$IS_TERMUX" = true ] || [[ "$CHOSEN_DIR" == *"storage/shared"* ]]; then
            git -C "$CHOSEN_DIR" config core.fileMode false
            echo -e "${GREEN}✓ Configured core.fileMode = false for Android shared storage.${RESET}"
        fi

        REMOTE_URL=$(prompt_input "Enter remote GitHub repository URL (press Enter to skip): " "")
        if [ -n "$REMOTE_URL" ]; then
            git -C "$CHOSEN_DIR" remote remove origin 2>/dev/null || true
            git -C "$CHOSEN_DIR" remote add origin "$REMOTE_URL"
            git -C "$CHOSEN_DIR" branch -M main 2>/dev/null || true
            echo -e "${GREEN}✓ Linked remote origin: $REMOTE_URL${RESET}"
        fi
    fi
fi

# 8. PATH Warning if necessary
echo
if [[ ":$PATH:" != *":$TARGET_BIN_DIR:"* ]]; then
    echo -e "${YELLOW}Warning: $TARGET_BIN_DIR is not currently in your \$PATH.${RESET}"
    echo "To use 'diary' from anywhere, add this line to your shell config (~/.zshrc, ~/.bashrc, etc.):"
    echo -e "  ${BOLD}export PATH=\"$TARGET_BIN_DIR:\$PATH\"${RESET}"
    echo
fi

echo -e "${GREEN}${BOLD}----------------------------------------${RESET}"
echo -e "${GREEN}${BOLD}CLI Diary installation complete! 🎉${RESET}"
echo "Run '${BOLD}diary help${RESET}' to get started."
