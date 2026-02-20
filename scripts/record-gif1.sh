#!/bin/bash
# record-gif1.sh — Fully automated GIF recording: "Enable Tor in 20 seconds"
#
# Records two GIFs:
#   demo/setup-tor-demo.gif       — Using prebuilt ISO download
#   demo/setup-tor-demo-build.gif — Building from source
#
# Prerequisites: VirtualBox, sshpass, asciinema, agg (auto-installed if missing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_DIR="$REPO_ROOT/demo"
BACKEND_DIR="$REPO_ROOT/backend"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Install dependencies ────────────────────────────────────────────────────
install_deps() {
    local missing=""
    command -v asciinema &>/dev/null || missing="$missing asciinema"
    command -v sshpass &>/dev/null || missing="$missing sshpass"
    command -v VBoxManage &>/dev/null || { echo -e "${RED}VirtualBox required. Install it first.${NC}"; exit 1; }

    if [ -n "$missing" ]; then
        echo -e "${YELLOW}Installing:${missing}${NC}"
        sudo apt-get update -qq && sudo apt-get install -y -qq $missing
    fi

    # agg: Rust-based asciinema-to-gif converter
    if ! command -v agg &>/dev/null; then
        echo -e "${YELLOW}Installing agg (asciinema GIF generator)...${NC}"
        local agg_url="https://github.com/asciinema/agg/releases/latest/download/agg-x86_64-unknown-linux-gnu"
        local agg_dest="${HOME}/.local/bin/agg"
        mkdir -p "$(dirname "$agg_dest")"
        curl -sL -o "$agg_dest" "$agg_url"
        chmod +x "$agg_dest"
        export PATH="${HOME}/.local/bin:$PATH"
        if ! agg --version &>/dev/null; then
            echo -e "${YELLOW}Prebuilt agg failed, trying cargo install...${NC}"
            rm -f "$agg_dest"
            cargo install --git https://github.com/asciinema/agg
        fi
    fi
}

# ── Ensure clean state ──────────────────────────────────────────────────────
ensure_clean_vm() {
    local vm="SelfPrivacy-Tor-Test"
    if VBoxManage showvminfo "$vm" &>/dev/null; then
        echo -e "${YELLOW}Cleaning up existing VM for fresh recording...${NC}"
        VBoxManage controlvm "$vm" poweroff 2>/dev/null || true
        sleep 2
        VBoxManage unregistervm "$vm" --delete 2>/dev/null || true
    fi
}

# ── Record a terminal session ───────────────────────────────────────────────
# $1 = output .cast file, $2 = script to execute inside the recording
record_session() {
    local cast_file="$1"
    local script_file="$2"

    # asciinema requires a PTY — use `script` to provide one
    script -q -c "asciinema rec \
        --cols 100 \
        --rows 30 \
        --idle-time-limit 3 \
        --command 'bash $script_file' \
        --overwrite \
        '$cast_file'" /dev/null
}

# ── Convert .cast to .gif ───────────────────────────────────────────────────
cast_to_gif() {
    local cast_file="$1"
    local gif_file="$2"

    echo -e "${YELLOW}Converting to GIF: ${gif_file}${NC}"
    agg \
        --font-size 14 \
        --speed 2 \
        --theme monokai \
        "$cast_file" \
        "$gif_file"
    echo -e "${GREEN}  Created: ${gif_file} ($(du -h "$gif_file" | cut -f1))${NC}"
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    echo -e "${GREEN}=== GIF 1: Enable Tor in 20 seconds ===${NC}"
    echo ""

    install_deps
    mkdir -p "$DEMO_DIR"

    # ── GIF 1a: Prebuilt ISO download flow ──────────────────────────────────
    echo -e "${CYAN}Recording GIF 1a: Prebuilt ISO download...${NC}"

    ensure_clean_vm

    # Create a script that drives build-and-run.sh non-interactively
    local script_download=$(mktemp /tmp/gif1a-XXXXXX.sh)
    cat > "$script_download" << INNEREOF
#!/bin/bash
cd "$BACKEND_DIR"
echo ""
echo "\$ cd backend && ./build-and-run.sh"
echo ""
# Non-interactive: download prebuilt, no custom key, force reinstall
SP_BUILD_MODE=download SP_VM_ACTION=reinstall bash build-and-run.sh
INNEREOF
    chmod +x "$script_download"

    local cast1a="$DEMO_DIR/setup-tor-demo.cast"
    record_session "$cast1a" "$script_download"
    cast_to_gif "$cast1a" "$DEMO_DIR/setup-tor-demo.gif"
    rm -f "$script_download" "$cast1a"

    # ── GIF 1b: Build from source flow ──────────────────────────────────────
    echo ""
    echo -e "${CYAN}Recording GIF 1b: Build from source...${NC}"

    ensure_clean_vm

    local script_build=$(mktemp /tmp/gif1b-XXXXXX.sh)
    cat > "$script_build" << INNEREOF
#!/bin/bash
cd "$BACKEND_DIR"
echo ""
echo "\$ cd backend && ./build-and-run.sh"
echo ""
# Non-interactive: build from source, no custom key, force reinstall
SP_BUILD_MODE=build SP_VM_ACTION=reinstall bash build-and-run.sh
INNEREOF
    chmod +x "$script_build"

    local cast1b="$DEMO_DIR/setup-tor-demo-build.cast"
    record_session "$cast1b" "$script_build"
    cast_to_gif "$cast1b" "$DEMO_DIR/setup-tor-demo-build.gif"
    rm -f "$script_build" "$cast1b"

    # ── Destroy Tor keys (security) ─────────────────────────────────────────
    echo ""
    echo -e "${YELLOW}Destroying Tor keys used during recording...${NC}"
    bash "$SCRIPT_DIR/scrub-and-push.sh" || true

    echo ""
    echo -e "${GREEN}=== GIF 1 recording complete! ===${NC}"
    echo -e "  ${CYAN}$DEMO_DIR/setup-tor-demo.gif${NC}"
    echo -e "  ${CYAN}$DEMO_DIR/setup-tor-demo-build.gif${NC}"
}

main "$@"
