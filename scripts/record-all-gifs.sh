#!/bin/bash
# record-all-gifs.sh — Record ALL demo GIFs using a single .onion domain
#
# Ensures every GIF shows the same .onion address by:
#   1. Recording GIF 1a (backend setup — prebuilt download)
#   2. Backing up the Tor keys from the running VM
#   3. Recording GIF 2 (Linux Flutter app — same VM, same .onion)
#   4. Destroying the VM for a clean GIF 1b recording
#   5. Recording GIF 1b (backend setup — build from source)
#   6. Restoring the backed-up Tor keys so .onion matches
#   7. Scrubbing all Tor keys (dead .onion, safe to push)
#
# Output:
#   demo/setup-tor-demo.gif         — Backend setup (download)
#   demo/setup-tor-demo-build.gif   — Backend setup (build from source)
#   demo/linux-app-tor-demo.gif     — Linux desktop Flutter app
#
# Prerequisites: VirtualBox, sshpass, asciinema, agg, Xvfb, xdotool, ffmpeg, gifsicle, Flutter SDK, Tor on host
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_DIR="$REPO_ROOT/demo"
BACKEND_DIR="$REPO_ROOT/backend"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password -o LogLevel=ERROR"
SSH_PORT=2222
TOR_KEY_BACKUP="/tmp/tor-key-backup-$$"
VM_NAME="SelfPrivacy-Tor-Test"

cleanup() {
    rm -rf "$TOR_KEY_BACKUP"
}
trap cleanup EXIT

do_ssh_cmd() {
    sshpass -p '' ssh -n $SSH_OPTS -p $SSH_PORT root@localhost "$@"
}

# ── Backup Tor keys from running VM ────────────────────────────────────────
backup_tor_keys() {
    echo -e "${YELLOW}Backing up Tor keys from VM...${NC}"
    mkdir -p "$TOR_KEY_BACKUP"
    sshpass -p '' scp $SSH_OPTS -P $SSH_PORT \
        root@localhost:/var/lib/tor/hidden_service/hs_ed25519_secret_key \
        "$TOR_KEY_BACKUP/hs_ed25519_secret_key" 2>/dev/null
    sshpass -p '' scp $SSH_OPTS -P $SSH_PORT \
        root@localhost:/var/lib/tor/hidden_service/hs_ed25519_public_key \
        "$TOR_KEY_BACKUP/hs_ed25519_public_key" 2>/dev/null
    echo -e "  ${GREEN}Keys backed up.${NC}"
}

# ── Restore Tor keys to running VM ─────────────────────────────────────────
restore_tor_keys() {
    echo -e "${YELLOW}Restoring Tor keys to VM (same .onion)...${NC}"
    do_ssh_cmd 'systemctl stop tor' 2>/dev/null || true
    sshpass -p '' scp $SSH_OPTS -P $SSH_PORT \
        "$TOR_KEY_BACKUP/hs_ed25519_secret_key" \
        root@localhost:/var/lib/tor/hidden_service/hs_ed25519_secret_key 2>/dev/null
    sshpass -p '' scp $SSH_OPTS -P $SSH_PORT \
        "$TOR_KEY_BACKUP/hs_ed25519_public_key" \
        root@localhost:/var/lib/tor/hidden_service/hs_ed25519_public_key 2>/dev/null
    do_ssh_cmd 'chown toranon:toranon /var/lib/tor/hidden_service/hs_ed25519_secret_key /var/lib/tor/hidden_service/hs_ed25519_public_key && chmod 600 /var/lib/tor/hidden_service/hs_ed25519_secret_key && rm -f /var/lib/tor/hidden_service/hostname && systemctl start tor' 2>/dev/null
    # Wait for .onion to appear
    local waited=0
    while [ $waited -lt 60 ]; do
        ONION=$(do_ssh_cmd cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
        if [ -n "$ONION" ]; then
            echo -e "  ${GREEN}Restored .onion: ${CYAN}$ONION${NC}"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    echo -e "${RED}Failed to restore .onion address${NC}"
    return 1
}

# ── Ensure clean VM state ──────────────────────────────────────────────────
ensure_clean_vm() {
    if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
        echo -e "${YELLOW}Cleaning up existing VM for fresh recording...${NC}"
        VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
        sleep 2
        VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
    fi
}

# ── Record asciinema session ────────────────────────────────────────────────
record_session() {
    local cast_file="$1"
    local script_file="$2"
    script -q -c "asciinema rec \
        --cols 100 \
        --rows 40 \
        --idle-time-limit 3 \
        --command 'bash $script_file' \
        --overwrite \
        '$cast_file'" /dev/null
}

# ── Compress .cast and convert to .gif ──────────────────────────────────────
cast_to_gif() {
    local cast_file="$1"
    local gif_file="$2"
    local compressed="${cast_file%.cast}-compressed.cast"

    echo -e "${YELLOW}Compressing recording...${NC}"
    python3 "$SCRIPT_DIR/compress-cast.py" "$cast_file" "$compressed" --hold-end 8

    echo -e "${YELLOW}Converting to GIF: ${gif_file}${NC}"
    agg \
        --font-size 14 \
        --speed 1 \
        --theme monokai \
        "$compressed" \
        "$gif_file"

    rm -f "$compressed"
    echo -e "${GREEN}  Created: ${gif_file} ($(du -h "$gif_file" | cut -f1))${NC}"
}

# ── Check recording dependencies ────────────────────────────────────────────
install_deps() {
    bash "$SCRIPT_DIR/requirements.sh" --gifs
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
main() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Recording ALL demo GIFs (single .onion domain)        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    install_deps
    mkdir -p "$DEMO_DIR"

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 1: Backend setup GIF (download) → creates the VM
    # ══════════════════════════════════════════════════════════════════════════
    echo -e "${BOLD}[Phase 1/4] Recording backend setup (download prebuilt)...${NC}"
    echo ""

    ensure_clean_vm

    local script_download=$(mktemp /tmp/gif1a-XXXXXX.sh)
    cat > "$script_download" << INNEREOF
#!/bin/bash
cd "$BACKEND_DIR"
echo ""
echo "\$ cd backend && ./build-and-run.sh"
echo ""
SP_BUILD_MODE=download SP_VM_ACTION=reinstall bash build-and-run.sh
INNEREOF
    chmod +x "$script_download"

    local cast1a="$DEMO_DIR/setup-tor-demo.cast"
    record_session "$cast1a" "$script_download"
    cast_to_gif "$cast1a" "$DEMO_DIR/setup-tor-demo.gif"
    rm -f "$script_download" "$cast1a"

    # Get the .onion from the now-running VM
    ONION=$(do_ssh_cmd cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
    echo -e "  ${BOLD}Shared .onion:${NC} ${CYAN}$ONION${NC}"

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 2: Backup Tor keys (same .onion for later phases)
    # ══════════════════════════════════════════════════════════════════════════
    backup_tor_keys

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 3: Linux Flutter app GIF (uses same running VM, same .onion)
    # ══════════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${BOLD}[Phase 2/4] Recording Linux Flutter app...${NC}"
    echo ""

    bash "$SCRIPT_DIR/record-gif2.sh"

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 4: Backend setup GIF (build from source) → new VM, same .onion
    # ══════════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${BOLD}[Phase 3/4] Recording backend setup (build from source)...${NC}"
    echo ""

    ensure_clean_vm

    local script_build=$(mktemp /tmp/gif1b-XXXXXX.sh)
    # Use SP_TOR_KEY to restore the same .onion
    cat > "$script_build" << INNEREOF
#!/bin/bash
cd "$BACKEND_DIR"
echo ""
echo "\$ cd backend && ./build-and-run.sh"
echo ""
SP_BUILD_MODE=build SP_VM_ACTION=reinstall SP_TOR_KEY="$TOR_KEY_BACKUP/hs_ed25519_secret_key" bash build-and-run.sh
INNEREOF
    chmod +x "$script_build"

    local cast1b="$DEMO_DIR/setup-tor-demo-build.cast"
    record_session "$cast1b" "$script_build"
    cast_to_gif "$cast1b" "$DEMO_DIR/setup-tor-demo-build.gif"
    rm -f "$script_build" "$cast1b"

    # ══════════════════════════════════════════════════════════════════════════
    # PHASE 5: Scrub Tor keys — .onion is now dead, safe to push
    # ══════════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${BOLD}[Phase 4/4] Scrubbing Tor keys...${NC}"
    echo ""

    # Destroy keys in backup
    rm -rf "$TOR_KEY_BACKUP"

    # Destroy keys on VM
    bash "$SCRIPT_DIR/scrub-and-push.sh" || true

    # ══════════════════════════════════════════════════════════════════════════
    # DONE
    # ══════════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              All GIFs recorded successfully!                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  All GIFs use .onion: ${CYAN}$ONION${NC} (now dead)"
    echo ""
    for gif in "$DEMO_DIR"/*.gif; do
        echo -e "  ${CYAN}$(basename "$gif")${NC}  ($(du -h "$gif" | cut -f1))"
    done
    echo ""
    echo -e "  ${GREEN}Safe to commit and push.${NC}"
}

main "$@"
