#!/bin/bash
# record-gif3.sh — Fully automated GIF recording: "Android VM over Tor"
#
# Records:
#   demo/android-vm-tor-demo.gif — Android x86 VM connecting to backend over Tor
#
# Uses VirtualBox screen capture (VBoxManage) to record the Android VM's
# display, then converts to GIF. No physical display needed.
#
# Prerequisites: Backend VM running, Android x86 VM, Tor on host,
#                ffmpeg, gifsicle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_DIR="$REPO_ROOT/demo"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password -o LogLevel=ERROR"
BACKEND_SSH_PORT=2222
ANDROID_VM_NAME="Android-x86-SelfPrivacy"
RECORD_SECONDS=60

# ── Install dependencies ────────────────────────────────────────────────────
install_deps() {
    local missing=""
    command -v ffmpeg &>/dev/null || missing="$missing ffmpeg"
    command -v gifsicle &>/dev/null || missing="$missing gifsicle"
    command -v sshpass &>/dev/null || missing="$missing sshpass"

    if [ -n "$missing" ]; then
        echo -e "${YELLOW}Installing:${missing}${NC}"
        sudo apt-get update -qq && sudo apt-get install -y -qq $missing
    fi
}

# ── Check prerequisites ────────────────────────────────────────────────────
check_prereqs() {
    # Backend VM must be running
    if ! sshpass -p '' ssh $SSH_OPTS -o ConnectTimeout=3 -p $BACKEND_SSH_PORT root@localhost true 2>/dev/null; then
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
    ONION=$(sshpass -p '' ssh $SSH_OPTS -p $BACKEND_SSH_PORT root@localhost cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
    if [ -z "$ONION" ]; then
        echo -e "${RED}Could not get .onion address from backend VM.${NC}"
        exit 1
    fi
    echo -e "  .onion address: ${CYAN}$ONION${NC}"
}

# ── Clean up on exit ────────────────────────────────────────────────────────
cleanup() {
    # Stop VBox recording if active
    VBoxManage controlvm "$ANDROID_VM_NAME" videocapture off 2>/dev/null || true
    rm -f /tmp/gif3-recording.webm /tmp/gif3-recording.mp4
}
trap cleanup EXIT

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    echo -e "${GREEN}=== GIF 3: Android VM over Tor ===${NC}"
    echo ""

    install_deps
    check_prereqs
    mkdir -p "$DEMO_DIR"

    # ── Ensure Android VM is running ────────────────────────────────────────
    if ! VBoxManage showvminfo "$ANDROID_VM_NAME" &>/dev/null; then
        echo -e "${YELLOW}Android VM not found. Creating it...${NC}"
        if [ -f "$SCRIPT_DIR/android-x86-vm.sh" ]; then
            bash "$SCRIPT_DIR/android-x86-vm.sh" create
            bash "$SCRIPT_DIR/android-x86-vm.sh" start
        else
            echo -e "${RED}Android VM script not found. Create the VM first.${NC}"
            exit 1
        fi
    else
        local state
        state=$(VBoxManage showvminfo "$ANDROID_VM_NAME" --machinereadable | grep "^VMState=" | cut -d'"' -f2)
        if [ "$state" != "running" ]; then
            echo -e "${YELLOW}Starting Android VM...${NC}"
            VBoxManage startvm "$ANDROID_VM_NAME" --type headless
            sleep 30  # Wait for Android to boot
        fi
    fi

    # Wait for ADB connection
    echo -e "${YELLOW}Waiting for ADB connection...${NC}"
    local adb_port=15555
    adb connect "127.0.0.1:${adb_port}" 2>/dev/null || true
    local waited=0
    while ! adb devices | grep -q "${adb_port}.*device$"; do
        sleep 3
        waited=$((waited + 3))
        if [ $waited -gt 90 ]; then
            echo -e "${RED}ADB connection timed out.${NC}"
            exit 1
        fi
        adb connect "127.0.0.1:${adb_port}" 2>/dev/null || true
        echo -n "."
    done
    echo -e "  ${GREEN}ADB connected.${NC}"

    # ── Set up Tor proxy on Android ─────────────────────────────────────────
    echo -e "${YELLOW}Setting up Tor proxy on Android...${NC}"
    # Forward host Tor SOCKS port to Android
    adb -s "127.0.0.1:${adb_port}" reverse tcp:8118 tcp:8118 2>/dev/null || true
    adb -s "127.0.0.1:${adb_port}" shell settings put global http_proxy 127.0.0.1:8118 2>/dev/null || true
    echo -e "  ${GREEN}Proxy configured.${NC}"

    # ── Start VirtualBox video capture ──────────────────────────────────────
    echo -e "${YELLOW}Starting screen recording (${RECORD_SECONDS}s)...${NC}"
    local webm_file="/tmp/gif3-recording.webm"
    VBoxManage modifyvm "$ANDROID_VM_NAME" --recording on \
        --recording-video-res 800x600 \
        --recording-video-rate 512 \
        --recording-video-fps 10 \
        --recording-file "$webm_file" 2>/dev/null || \
    VBoxManage controlvm "$ANDROID_VM_NAME" videocapture on 2>/dev/null || true
    sleep 2

    # ── Launch the SelfPrivacy app on Android ───────────────────────────────
    echo -e "${YELLOW}Launching SelfPrivacy app...${NC}"
    adb -s "127.0.0.1:${adb_port}" shell am start -n org.selfprivacy.app/org.selfprivacy.app.MainActivity 2>/dev/null || true
    sleep 5

    # ── Automate: enter .onion address ──────────────────────────────────────
    echo -e "${YELLOW}Automating setup flow via ADB...${NC}"

    # Domain field should have autofocus
    adb -s "127.0.0.1:${adb_port}" shell input text "$ONION" 2>/dev/null || true
    sleep 1

    # Tab to token field
    adb -s "127.0.0.1:${adb_port}" shell input keyevent KEYCODE_TAB 2>/dev/null || true
    sleep 0.5

    # Type token
    adb -s "127.0.0.1:${adb_port}" shell input text "test-token-for-tor-development" 2>/dev/null || true
    sleep 1

    # Tab to Connect and press
    for _ in 1 2 3; do
        adb -s "127.0.0.1:${adb_port}" shell input keyevent KEYCODE_TAB 2>/dev/null || true
        sleep 0.3
    done
    adb -s "127.0.0.1:${adb_port}" shell input keyevent KEYCODE_DPAD_CENTER 2>/dev/null || true

    # Wait for connection and dashboard
    echo -e "${YELLOW}Waiting for app to connect...${NC}"
    sleep "$((RECORD_SECONDS - 15))"

    # ── Stop recording ──────────────────────────────────────────────────────
    echo -e "${YELLOW}Stopping recording...${NC}"
    VBoxManage controlvm "$ANDROID_VM_NAME" videocapture off 2>/dev/null || \
    VBoxManage modifyvm "$ANDROID_VM_NAME" --recording off 2>/dev/null || true
    sleep 2

    # ── Convert to GIF ──────────────────────────────────────────────────────
    echo -e "${YELLOW}Converting to GIF...${NC}"
    local gif="$DEMO_DIR/android-vm-tor-demo.gif"

    # If VBox produced a webm, convert first to mp4, then to gif
    if [ -f "$webm_file" ]; then
        ffmpeg -y -i "$webm_file" -c:v libx264 -preset ultrafast /tmp/gif3-recording.mp4 2>/dev/null

        ffmpeg -y -i /tmp/gif3-recording.mp4 \
            -vf "fps=8,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
            "$gif" 2>/dev/null

        if command -v gifsicle &>/dev/null; then
            gifsicle --optimize=3 --lossy=80 -o "$gif" "$gif"
        fi

        echo -e "${GREEN}  Created: ${gif} ($(du -h "$gif" | cut -f1))${NC}"
    else
        echo -e "${RED}  Recording file not found. VBox video capture may not be supported.${NC}"
        echo -e "${YELLOW}  Falling back to screenshot sequence...${NC}"

        # Fallback: take periodic screenshots and assemble into GIF
        local tmp_frames="/tmp/gif3-frames"
        mkdir -p "$tmp_frames"
        for i in $(seq 1 $((RECORD_SECONDS / 2))); do
            VBoxManage controlvm "$ANDROID_VM_NAME" screenshotpng "${tmp_frames}/frame-$(printf '%04d' $i).png" 2>/dev/null || true
            sleep 2
        done

        # Assemble frames into GIF
        ffmpeg -y -framerate 2 -i "${tmp_frames}/frame-%04d.png" \
            -vf "scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
            "$gif" 2>/dev/null

        if command -v gifsicle &>/dev/null; then
            gifsicle --optimize=3 --lossy=80 -o "$gif" "$gif"
        fi

        rm -rf "$tmp_frames"
        echo -e "${GREEN}  Created: ${gif} ($(du -h "$gif" | cut -f1))${NC}"
    fi

    rm -f /tmp/gif3-recording.webm /tmp/gif3-recording.mp4

    echo ""
    echo -e "${GREEN}=== GIF 3 recording complete! ===${NC}"
    echo -e "  ${CYAN}$gif${NC}"
}

main "$@"
