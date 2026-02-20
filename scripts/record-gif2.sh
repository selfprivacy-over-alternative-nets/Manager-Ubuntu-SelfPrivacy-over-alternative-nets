#!/bin/bash
# record-gif2.sh — Fully automated GIF recording: "Local Ubuntu setup wizard"
#
# Records:
#   demo/linux-app-tor-demo.gif — Linux desktop Flutter app connecting over Tor
#
# This uses Xvfb (virtual framebuffer) + ffmpeg to capture the GUI app,
# then converts to GIF. Fully headless — no physical display needed.
#
# Prerequisites: VirtualBox VM running, Tor on host (port 9050),
#                Flutter SDK, Xvfb, ffmpeg, gifsicle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_DIR="$REPO_ROOT/demo"
FLUTTER_DIR="$REPO_ROOT/flutter-app/selfprivacy.org.app"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password -o LogLevel=ERROR"
SSH_PORT=2222
DISPLAY_NUM=99
SCREEN_W=1280
SCREEN_H=720
RECORD_SECONDS=45

# ── Install dependencies ────────────────────────────────────────────────────
install_deps() {
    local missing=""
    command -v Xvfb &>/dev/null || missing="$missing xvfb"
    command -v ffmpeg &>/dev/null || missing="$missing ffmpeg"
    command -v gifsicle &>/dev/null || missing="$missing gifsicle"
    command -v xdotool &>/dev/null || missing="$missing xdotool"
    command -v sshpass &>/dev/null || missing="$missing sshpass"

    if [ -n "$missing" ]; then
        echo -e "${YELLOW}Installing:${missing}${NC}"
        sudo apt-get update -qq && sudo apt-get install -y -qq $missing
    fi
}

# ── Check prerequisites ────────────────────────────────────────────────────
check_prereqs() {
    # VM must be running
    if ! sshpass -p '' ssh $SSH_OPTS -o ConnectTimeout=3 -p $SSH_PORT root@localhost true 2>/dev/null; then
        echo -e "${RED}Backend VM is not running. Start it first:${NC}"
        echo -e "  ${CYAN}cd backend && ./build-and-run.sh${NC}"
        exit 1
    fi

    # Tor must be running on host
    if ! ss -tlnp 2>/dev/null | grep -q ':9050 '; then
        echo -e "${RED}Tor is not running on host port 9050.${NC}"
        echo -e "  ${CYAN}sudo apt install tor && sudo systemctl start tor${NC}"
        exit 1
    fi

    # Get .onion address
    ONION=$(sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
    if [ -z "$ONION" ]; then
        echo -e "${RED}Could not get .onion address from VM.${NC}"
        exit 1
    fi
    echo -e "  .onion address: ${CYAN}$ONION${NC}"

    # Flutter SDK
    if ! command -v flutter &>/dev/null; then
        echo -e "${RED}Flutter SDK not found. Install it first.${NC}"
        exit 1
    fi
}

# ── Clean up on exit ────────────────────────────────────────────────────────
cleanup() {
    # Kill Xvfb if we started it
    if [ -n "${XVFB_PID:-}" ]; then
        kill "$XVFB_PID" 2>/dev/null || true
    fi
    # Kill ffmpeg if running
    if [ -n "${FFMPEG_PID:-}" ]; then
        kill "$FFMPEG_PID" 2>/dev/null || true
    fi
    # Kill Flutter app if running
    if [ -n "${APP_PID:-}" ]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    rm -f /tmp/gif2-recording.mp4
}
trap cleanup EXIT

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    echo -e "${GREEN}=== GIF 2: Linux Desktop App over Tor ===${NC}"
    echo ""

    install_deps
    check_prereqs
    mkdir -p "$DEMO_DIR"

    # ── Build the Flutter app ───────────────────────────────────────────────
    echo -e "${YELLOW}Building Flutter Linux app...${NC}"
    cd "$FLUTTER_DIR"
    flutter pub get --no-example 2>/dev/null
    flutter build linux --debug 2>&1 | tail -5

    BINARY="build/linux/x64/debug/bundle/selfprivacy"
    if [ ! -f "$BINARY" ]; then
        echo -e "${RED}Build failed — binary not found.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}Build complete.${NC}"

    # ── Start virtual display ───────────────────────────────────────────────
    echo -e "${YELLOW}Starting virtual display (Xvfb :${DISPLAY_NUM})...${NC}"
    Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_W}x${SCREEN_H}x24 &
    XVFB_PID=$!
    sleep 1
    export DISPLAY=:${DISPLAY_NUM}
    echo -e "  ${GREEN}Virtual display ready.${NC}"

    # ── Clear app data for fresh setup screen ───────────────────────────────
    rm -rf ~/.local/share/selfprivacy/*.hive ~/.local/share/selfprivacy/*.lock 2>/dev/null || true

    # ── Start screen recording ──────────────────────────────────────────────
    echo -e "${YELLOW}Starting screen recording (${RECORD_SECONDS}s)...${NC}"
    ffmpeg -y -f x11grab -video_size ${SCREEN_W}x${SCREEN_H} -framerate 10 \
        -i :${DISPLAY_NUM} -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
        /tmp/gif2-recording.mp4 &>/dev/null &
    FFMPEG_PID=$!
    sleep 1

    # ── Launch the Flutter app ──────────────────────────────────────────────
    echo -e "${YELLOW}Launching SelfPrivacy app...${NC}"
    cd "$FLUTTER_DIR"
    "$BINARY" &
    APP_PID=$!

    # Wait for the app window to appear
    sleep 5

    # ── Automate: type .onion address and connect ───────────────────────────
    echo -e "${YELLOW}Automating setup flow...${NC}"

    # Focus the app window
    xdotool search --name "selfprivacy" windowactivate --sync 2>/dev/null || \
    xdotool search --name "SelfPrivacy" windowactivate --sync 2>/dev/null || \
    sleep 2

    # The setup screen should have the domain field focused
    # Type the .onion address
    sleep 2
    xdotool type --delay 50 "$ONION"
    sleep 1

    # Tab to token field and type token
    xdotool key Tab
    sleep 0.5
    xdotool type --delay 30 "test-token-for-tor-development"
    sleep 1

    # Tab to Connect button and press Enter
    xdotool key Tab Tab Tab
    sleep 0.5
    xdotool key Return
    sleep 1

    # Let the app connect and show the dashboard
    echo -e "${YELLOW}Waiting for app to connect (${RECORD_SECONDS}s total)...${NC}"
    local remaining=$((RECORD_SECONDS - 15))
    sleep "$remaining"

    # ── Stop recording ──────────────────────────────────────────────────────
    echo -e "${YELLOW}Stopping recording...${NC}"
    kill "$FFMPEG_PID" 2>/dev/null || true
    FFMPEG_PID=""
    sleep 1

    kill "$APP_PID" 2>/dev/null || true
    APP_PID=""

    kill "$XVFB_PID" 2>/dev/null || true
    XVFB_PID=""

    # ── Convert to GIF ──────────────────────────────────────────────────────
    echo -e "${YELLOW}Converting to GIF...${NC}"
    local gif="$DEMO_DIR/linux-app-tor-demo.gif"

    # Convert mp4 to gif with palette optimization
    ffmpeg -y -i /tmp/gif2-recording.mp4 \
        -vf "fps=8,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
        "$gif" 2>/dev/null

    # Optimize with gifsicle
    if command -v gifsicle &>/dev/null; then
        gifsicle --optimize=3 --lossy=80 -o "$gif" "$gif"
    fi

    echo -e "${GREEN}  Created: ${gif} ($(du -h "$gif" | cut -f1))${NC}"
    rm -f /tmp/gif2-recording.mp4

    echo ""
    echo -e "${GREEN}=== GIF 2 recording complete! ===${NC}"
    echo -e "  ${CYAN}$gif${NC}"
}

main "$@"
