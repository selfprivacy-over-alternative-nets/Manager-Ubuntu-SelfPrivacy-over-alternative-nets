#!/bin/bash
# requirements.sh — Install all dependencies for SelfPrivacy over Tor
#
# Usage:
#   ./scripts/requirements.sh              # Backend only (VirtualBox, sshpass, tor)
#   ./scripts/requirements.sh --app-linux  # + Flutter SDK + Linux build deps
#   ./scripts/requirements.sh --app-android # + Flutter SDK + Android SDK
#   ./scripts/requirements.sh --gifs       # + asciinema, agg, Xvfb, ffmpeg, etc.
#   ./scripts/requirements.sh --all        # Everything
#   ./scripts/requirements.sh --check      # Dry-run: show what's missing
#
# Combines all requirements that were previously scattered across individual scripts.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Parse arguments ───────────────────────────────────────────────────────
INSTALL_BACKEND=false
INSTALL_APP_LINUX=false
INSTALL_APP_ANDROID=false
INSTALL_GIFS=false
CHECK_ONLY=false

if [ $# -eq 0 ]; then
    INSTALL_BACKEND=true
fi

for arg in "$@"; do
    case "$arg" in
        --app-linux)    INSTALL_BACKEND=true; INSTALL_APP_LINUX=true ;;
        --app-android)  INSTALL_BACKEND=true; INSTALL_APP_ANDROID=true ;;
        --gifs)         INSTALL_BACKEND=true; INSTALL_APP_LINUX=true; INSTALL_GIFS=true ;;
        --all)          INSTALL_BACKEND=true; INSTALL_APP_LINUX=true; INSTALL_APP_ANDROID=true; INSTALL_GIFS=true ;;
        --check)        CHECK_ONLY=true; INSTALL_BACKEND=true; INSTALL_APP_LINUX=true; INSTALL_APP_ANDROID=true; INSTALL_GIFS=true ;;
        --help|-h)
            echo "Usage: ./scripts/requirements.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)          Backend only (VirtualBox, sshpass, tor)"
            echo "  --app-linux     + Flutter SDK + Linux desktop build dependencies"
            echo "  --app-android   + Flutter SDK + Android SDK"
            echo "  --gifs          + GIF recording tools (asciinema, agg, Xvfb, ffmpeg)"
            echo "  --all           Everything"
            echo "  --check         Dry-run: show what's missing without installing"
            echo "  --help          Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────
APT_PACKAGES=""
MISSING_TOOLS=""
MISSING_SDKS=""

need_apt() {
    local pkg="$1"
    local cmd="${2:-$1}"
    if ! command -v "$cmd" &>/dev/null; then
        APT_PACKAGES="$APT_PACKAGES $pkg"
        MISSING_TOOLS="$MISSING_TOOLS $cmd"
    fi
}

need_apt_lib() {
    local pkg="$1"
    if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
        APT_PACKAGES="$APT_PACKAGES $pkg"
        MISSING_TOOLS="$MISSING_TOOLS $pkg"
    fi
}

check_sdk() {
    local name="$1"
    local cmd="$2"
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_SDKS="$MISSING_SDKS $name"
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# COLLECT REQUIREMENTS
# ══════════════════════════════════════════════════════════════════════════

# ── Backend ───────────────────────────────────────────────────────────────
if $INSTALL_BACKEND; then
    need_apt virtualbox VBoxManage
    need_apt sshpass sshpass
    need_apt tor tor
    need_apt openssl openssl
    need_apt python3 python3
fi

# ── Flutter SDK (shared by Linux & Android) ──────────────────────────────
if $INSTALL_APP_LINUX || $INSTALL_APP_ANDROID; then
    check_sdk "Flutter SDK" flutter
    need_apt git git
    need_apt curl curl
    need_apt unzip unzip
    need_apt xz-utils xz
    need_apt zip zip
fi

# ── Linux desktop app ────────────────────────────────────────────────────
if $INSTALL_APP_LINUX; then
    need_apt ninja-build ninja
    need_apt clang clang
    need_apt cmake cmake
    need_apt pkg-config pkg-config
    need_apt_lib libgtk-3-dev
    need_apt_lib libsecret-1-dev
    need_apt_lib libjsoncpp-dev
    need_apt_lib libblkid-dev
    need_apt_lib liblzma-dev
    need_apt_lib libstdc++-12-dev
    need_apt xdg-user-dirs xdg-user-dirs
    need_apt gnome-keyring gnome-keyring
fi

# ── Android app ──────────────────────────────────────────────────────────
if $INSTALL_APP_ANDROID; then
    check_sdk "Android SDK" adb
fi

# ── GIF recording ────────────────────────────────────────────────────────
if $INSTALL_GIFS; then
    need_apt asciinema asciinema
    need_apt xvfb Xvfb
    need_apt ffmpeg ffmpeg
    need_apt gifsicle gifsicle
    need_apt xdotool xdotool
    check_sdk "agg (asciinema GIF generator)" agg
fi

# ══════════════════════════════════════════════════════════════════════════
# REPORT / INSTALL
# ══════════════════════════════════════════════════════════════════════════

# Deduplicate apt packages
APT_PACKAGES=$(echo "$APT_PACKAGES" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

if [ -z "$APT_PACKAGES" ] && [ -z "$MISSING_SDKS" ]; then
    echo -e "${GREEN}All dependencies are installed.${NC}"
    exit 0
fi

# ── Show what's needed ───────────────────────────────────────────────────
if [ -n "$APT_PACKAGES" ]; then
    echo -e "${BOLD}APT packages needed:${NC} ${CYAN}$APT_PACKAGES${NC}"
fi

if [ -n "$MISSING_SDKS" ]; then
    echo ""
    echo -e "${BOLD}SDKs/tools to install manually:${NC}"
    for sdk in $MISSING_SDKS; do
        case "$sdk" in
            "Flutter SDK")
                echo -e "  ${YELLOW}Flutter SDK${NC} — install to /opt/flutter:"
                echo -e "    ${CYAN}curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.2-stable.tar.xz | sudo tar xJf - -C /opt${NC}"
                echo -e "    ${CYAN}echo 'export PATH=\"/opt/flutter/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc${NC}"
                ;;
            "Android SDK")
                echo -e "  ${YELLOW}Android SDK${NC} — install Android Studio or command-line tools:"
                echo -e "    ${CYAN}mkdir -p ~/Android/Sdk && cd ~/Android/Sdk${NC}"
                echo -e "    ${CYAN}curl -sL \"https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip\" -o cmdline-tools.zip${NC}"
                echo -e "    ${CYAN}unzip cmdline-tools.zip && mkdir -p cmdline-tools && mv cmdline-tools cmdline-tools/latest${NC}"
                echo -e "    ${CYAN}export ANDROID_HOME=~/Android/Sdk${NC}"
                echo -e "    ${CYAN}yes | \$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses${NC}"
                echo -e "    ${CYAN}\$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \"platforms;android-35\" \"build-tools;36.1.0\" \"platform-tools\"${NC}"
                echo -e "    ${CYAN}flutter config --android-sdk ~/Android/Sdk${NC}"
                ;;
            "agg (asciinema GIF generator)")
                echo -e "  ${YELLOW}agg${NC} — asciinema GIF generator:"
                echo -e "    ${CYAN}mkdir -p ~/.local/bin${NC}"
                echo -e "    ${CYAN}curl -sL -o ~/.local/bin/agg https://github.com/asciinema/agg/releases/latest/download/agg-x86_64-unknown-linux-gnu${NC}"
                echo -e "    ${CYAN}chmod +x ~/.local/bin/agg${NC}"
                ;;
        esac
    done
fi

if $CHECK_ONLY; then
    echo ""
    echo -e "${YELLOW}Dry run — nothing installed. Run without --check to install.${NC}"
    exit 0
fi

# ── Install APT packages ────────────────────────────────────────────────
if [ -n "$APT_PACKAGES" ]; then
    echo ""
    echo -e "${YELLOW}Installing APT packages...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq $APT_PACKAGES
    echo -e "${GREEN}APT packages installed.${NC}"
fi

# ── Install agg if needed ────────────────────────────────────────────────
if $INSTALL_GIFS && ! command -v agg &>/dev/null; then
    echo ""
    echo -e "${YELLOW}Installing agg...${NC}"
    mkdir -p "${HOME}/.local/bin"
    curl -sL -o "${HOME}/.local/bin/agg" \
        "https://github.com/asciinema/agg/releases/latest/download/agg-x86_64-unknown-linux-gnu"
    chmod +x "${HOME}/.local/bin/agg"
    export PATH="${HOME}/.local/bin:$PATH"
    if agg --version &>/dev/null; then
        echo -e "${GREEN}agg installed.${NC}"
    else
        echo -e "${RED}agg binary failed. Install manually: cargo install --git https://github.com/asciinema/agg${NC}"
    fi
fi

# ── SDK reminders ────────────────────────────────────────────────────────
if [ -n "$MISSING_SDKS" ]; then
    echo ""
    echo -e "${YELLOW}Manual SDK installation still needed (see instructions above).${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}All dependencies installed.${NC}"
