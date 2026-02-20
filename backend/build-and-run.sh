#!/bin/bash
# build-and-run.sh — Single entry point for SelfPrivacy over Tor
#
# Usage:
#   ./build-and-run.sh                  # Setup backend VM (interactive)
#   ./build-and-run.sh --info           # Print credentials for running VM
#   ./build-and-run.sh --app-linux      # Build & run SelfPrivacy app on Linux
#   ./build-and-run.sh --app-android    # Build & deploy app to Android device
#   ./build-and-run.sh --trust-cert     # Trust VM cert on Ubuntu
#   ./build-and-run.sh --trust-cert-android  # Push VM cert to Android device
#
# Non-interactive mode (for CI/recording scripts):
#   SP_BUILD_MODE=download|build  — skip ISO source prompt
#   SP_TOR_KEY=/path/to/key       — use custom Tor key (empty = generate new)
#   SP_VM_ACTION=start|reinstall  — skip existing-VM prompt
set -e

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Configuration ───────────────────────────────────────────────────────────
VM_NAME="SelfPrivacy-Tor-Test"
VM_MEMORY=2048
VM_CPUS=2
VM_DISK_SIZE=10240
SSH_PORT=2222
GITHUB_REPO="selfprivacy-over-tor/Manager-Ubuntu-SelfPrivacy-Over-Tor"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password -o LogLevel=ERROR"

# ── Helpers ─────────────────────────────────────────────────────────────────
ask_yn() {
    # Ask a yes/no question. $1=prompt, $2=default (y/n)
    local prompt="$1" default="${2:-n}"
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    read -r -p "$(echo -e "$prompt")" answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

do_ssh() {
    sshpass -p '' ssh -tt $SSH_OPTS -p $SSH_PORT root@localhost "$@"
}

do_ssh_cmd() {
    sshpass -p '' ssh -n $SSH_OPTS -p $SSH_PORT root@localhost "$@"
}

wait_for_ssh() {
    local max_wait="${1:-180}"
    local elapsed=0
    echo -n "  Waiting for VM to be reachable..."
    while [ $elapsed -lt $max_wait ]; do
        if sshpass -p '' ssh -n $SSH_OPTS -o ConnectTimeout=2 -p $SSH_PORT root@localhost true 2>/dev/null; then
            echo ""
            echo -e "  ${GREEN}Connected!${NC}"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    echo -e "  ${RED}Timed out after ${max_wait}s${NC}"
    return 1
}

wait_for_onion() {
    local max_wait="${1:-120}"
    local elapsed=0
    ONION=""
    echo -n "  Waiting for Tor to publish .onion address..."
    while [ $elapsed -lt $max_wait ]; do
        ONION=$(do_ssh_cmd cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
        if [ -n "$ONION" ]; then
            echo ""
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    return 1
}

print_success() {
    # Fetch credentials from VM
    local nc_pass
    nc_pass=$(do_ssh_cmd 'cat /var/lib/nextcloud/admin-pass 2>/dev/null' 2>/dev/null || echo "(not yet available)")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              SelfPrivacy Tor VM is ready!                   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}.onion address:${NC}    ${CYAN}$ONION${NC}"
    echo -e "  ${BOLD}API token:${NC}         ${CYAN}test-token-for-tor-development${NC}"
    echo ""
    echo -e "  ${BOLD}Nextcloud:${NC}"
    echo -e "    URL:       ${CYAN}https://$ONION/nextcloud/${NC}"
    echo -e "    Username:  ${CYAN}admin${NC}"
    echo -e "    Password:  ${CYAN}$nc_pass${NC}"
    echo ""
    echo -e "  ${BOLD}Services:${NC}"
    echo -e "    SelfPrivacy API  ${CYAN}https://$ONION/api/${NC}"
    echo -e "    Nextcloud        ${CYAN}https://$ONION/nextcloud/${NC}"
    echo -e "    Gitea            ${CYAN}https://$ONION/git/${NC}"
    echo -e "    Jitsi Meet       ${CYAN}https://$ONION/jitsi/${NC}"
    echo -e "    Prometheus       ${CYAN}https://$ONION/prometheus/${NC}"
    echo ""
    echo -e "  ${BOLD}SSH:${NC}"
    echo -e "    ${CYAN}sshpass -p '' ssh -p $SSH_PORT root@localhost${NC}"
    echo ""
    echo -e "  ${BOLD}Watch live requests:${NC}"
    echo -e "    ${CYAN}sshpass -p '' ssh -p $SSH_PORT root@localhost journalctl -u nginx -u selfprivacy-api -f${NC}"
    echo ""
    echo -e "  ${BOLD}Record demo GIFs:${NC}"
    echo -e "    ${CYAN}./scripts/record-all-gifs.sh${NC}  (all GIFs, same .onion)"
    echo ""
}

# ── Subcommands ───────────────────────────────────────────────────────────
require_vm() {
    ONION=$(do_ssh_cmd cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
    if [ -z "$ONION" ]; then
        echo -e "${RED}Error: VM is not running or .onion address not available.${NC}" >&2
        echo -e "  Run ${CYAN}./build-and-run.sh${NC} first to set up the backend." >&2
        exit 1
    fi
}

case "${1:-}" in
    --info)
        require_vm
        print_success
        exit 0
        ;;
    --app-linux)
        require_vm
        shift
        exec bash "$SCRIPT_DIR/../scripts/record-gif2.sh" "$@"
        ;;
    --app-android)
        require_vm
        shift
        exec bash "$SCRIPT_DIR/../scripts/deploy-to-phone.sh" "$@"
        ;;
    --trust-cert)
        require_vm
        shift
        exec bash "$SCRIPT_DIR/../scripts/trust-cert.sh" "$@"
        ;;
    --trust-cert-android)
        require_vm
        shift
        exec bash "$SCRIPT_DIR/../scripts/trust-cert-android.sh" "$@"
        ;;
    --help|-h)
        echo "Usage: ./build-and-run.sh [COMMAND]"
        echo ""
        echo "Commands:"
        echo "  (none)               Setup backend VM (interactive)"
        echo "  --info               Print credentials for running VM"
        echo "  --app-linux          Build & run SelfPrivacy app on Linux desktop"
        echo "  --app-android        Build & deploy SelfPrivacy app to Android device"
        echo "  --trust-cert         Trust the VM's self-signed cert on Ubuntu"
        echo "  --trust-cert-android Push the VM's cert to Android device"
        echo "  --help               Show this help"
        echo ""
        echo "Environment variables (non-interactive backend setup):"
        echo "  SP_BUILD_MODE=download|build"
        echo "  SP_VM_ACTION=start|reinstall"
        echo "  SP_TOR_KEY=/path/to/hs_ed25519_secret_key"
        exit 0
        ;;
esac

# ── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     SelfPrivacy over Tor — Backend Setup        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ── Check dependencies ──────────────────────────────────────────────────────
echo -e "${BOLD}Checking dependencies...${NC}"
MISSING=""
if ! command -v VBoxManage &>/dev/null; then MISSING="$MISSING virtualbox"; fi
if ! command -v sshpass &>/dev/null; then MISSING="$MISSING sshpass"; fi

if [ -n "$MISSING" ]; then
    echo -e "${RED}Missing:${MISSING}${NC}"
    echo ""
    echo -e "  Install them with: ${CYAN}sudo apt install${MISSING}${NC}"
    exit 1
fi
echo -e "  ${GREEN}All dependencies found.${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# EXISTING VM DETECTED?
# ══════════════════════════════════════════════════════════════════════════════
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "^VMState=" | cut -d'"' -f2)

    if [ "$STATE" = "running" ]; then
        echo -e "${GREEN}Your SelfPrivacy VM is already running!${NC}"
        echo ""

        ONION=$(do_ssh_cmd cat /var/lib/tor/hidden_service/hostname 2>/dev/null || echo "")
        if [ -n "$ONION" ]; then
            print_success
        fi

        # Non-interactive: SP_VM_ACTION=reinstall forces clean install
        if [ "${SP_VM_ACTION:-}" = "reinstall" ]; then
            choice=4
        else
            echo -e "${BOLD}What would you like to do?${NC}"
            echo ""
            echo -e "  ${CYAN}1${NC}) Nothing — keep it running (default)"
            echo -e "  ${CYAN}2${NC}) Restart with a new .onion address"
            echo -e "  ${CYAN}3${NC}) Restart with a custom Tor private key"
            echo -e "  ${CYAN}4${NC}) Full clean reinstall (destroys everything)"
            echo ""
            read -r -p "$(echo -e "  Your choice [${CYAN}1${NC}]: ")" choice
            choice="${choice:-1}"
        fi

        case "$choice" in
            1)
                echo -e "${GREEN}OK, leaving VM as-is. Bye!${NC}"
                exit 0
                ;;
            2)
                echo -e "${YELLOW}Generating new .onion address...${NC}"
                do_ssh_cmd 'rm -f /var/lib/tor/hidden_service/hs_ed25519_secret_key /var/lib/tor/hidden_service/hs_ed25519_public_key /var/lib/tor/hidden_service/hostname && systemctl restart tor' 2>/dev/null
                sleep 3
                wait_for_onion
                print_success
                exit 0
                ;;
            3)
                echo ""
                echo -e "  Enter the path to your ${CYAN}hs_ed25519_secret_key${NC} file:"
                read -r -p "  Path: " keyfile
                if [ ! -f "$keyfile" ]; then
                    echo -e "${RED}File not found: $keyfile${NC}"
                    exit 1
                fi
                echo -e "${YELLOW}Uploading key and restarting Tor...${NC}"
                do_ssh_cmd 'systemctl stop tor' 2>/dev/null
                sshpass -p '' scp $SSH_OPTS -P $SSH_PORT "$keyfile" root@localhost:/var/lib/tor/hidden_service/hs_ed25519_secret_key 2>/dev/null
                do_ssh_cmd 'chown toranon:toranon /var/lib/tor/hidden_service/hs_ed25519_secret_key && chmod 600 /var/lib/tor/hidden_service/hs_ed25519_secret_key && rm -f /var/lib/tor/hidden_service/hs_ed25519_public_key /var/lib/tor/hidden_service/hostname && systemctl start tor' 2>/dev/null
                sleep 3
                wait_for_onion
                print_success
                exit 0
                ;;
            4)
                echo -e "${YELLOW}Stopping and deleting VM...${NC}"
                VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
                sleep 2
                VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
                echo -e "${GREEN}VM deleted. Continuing with fresh install...${NC}"
                echo ""
                ;;
            *)
                echo -e "${RED}Unknown choice. Exiting.${NC}"
                exit 1
                ;;
        esac

    else
        # VM exists but is stopped
        echo -e "${YELLOW}Your SelfPrivacy VM exists but is stopped.${NC}"
        echo ""

        if [ "${SP_VM_ACTION:-}" = "reinstall" ]; then
            choice=2
        elif [ "${SP_VM_ACTION:-}" = "start" ]; then
            choice=1
        else
            echo -e "  ${CYAN}1${NC}) Start it (default)"
            echo -e "  ${CYAN}2${NC}) Full clean reinstall"
            echo ""
            read -r -p "$(echo -e "  Your choice [${CYAN}1${NC}]: ")" choice
            choice="${choice:-1}"
        fi

        case "$choice" in
            1)
                echo -e "${YELLOW}Starting VM...${NC}"
                ssh-keygen -R '[localhost]:2222' 2>/dev/null || true
                VBoxManage startvm "$VM_NAME" --type headless
                wait_for_ssh
                wait_for_onion
                print_success
                exit 0
                ;;
            2)
                echo -e "${YELLOW}Deleting VM...${NC}"
                VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
                echo -e "${GREEN}VM deleted. Continuing with fresh install...${NC}"
                echo ""
                ;;
            *)
                echo -e "${RED}Unknown choice. Exiting.${NC}"
                exit 1
                ;;
        esac
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# FRESH INSTALL
# ══════════════════════════════════════════════════════════════════════════════

# ── Step 1: Get the ISO ─────────────────────────────────────────────────────
# Non-interactive: SP_BUILD_MODE=download|build
if [ "${SP_BUILD_MODE:-}" = "download" ]; then
    build_choice=1
elif [ "${SP_BUILD_MODE:-}" = "build" ]; then
    build_choice=2
else
    echo -e "${BOLD}How would you like to get the NixOS image?${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) Download a prebuilt image (fast — a few minutes)"
    echo -e "  ${CYAN}2${NC}) Build from source code (slow — can take 30+ minutes)"
    echo ""
    read -r -p "$(echo -e "  Your choice [${CYAN}1${NC}]: ")" build_choice
    build_choice="${build_choice:-1}"
fi

ISO_PATH=""
case "$build_choice" in
    1)
        echo ""
        echo -e "${YELLOW}Step 1/7: Downloading prebuilt ISO...${NC}"

        # Get the latest release ISO URL from GitHub
        RELEASE_URL=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
            | grep -o '"browser_download_url": *"[^"]*\.iso"' \
            | head -1 \
            | cut -d'"' -f4 || true)

        if [ -z "$RELEASE_URL" ]; then
            echo -e "${YELLOW}  No prebuilt ISO found in GitHub releases.${NC}"
            echo -e "${YELLOW}  Falling back to building from source...${NC}"
            build_choice=2
        else
            ISO_DIR="$SCRIPT_DIR/.cache"
            mkdir -p "$ISO_DIR"
            ISO_FILE="$ISO_DIR/selfprivacy-tor.iso"

            if [ -f "$ISO_FILE" ]; then
                echo -e "  ${GREEN}Using cached ISO: $ISO_FILE${NC}"
            else
                echo -e "  Downloading from: ${CYAN}$RELEASE_URL${NC}"
                curl -L --progress-bar -o "$ISO_FILE" "$RELEASE_URL"
                echo -e "  ${GREEN}Download complete!${NC}"
            fi
            ISO_PATH="$ISO_FILE"
        fi
        ;;
esac

if [ "$build_choice" = "2" ]; then
    echo ""
    echo -e "${YELLOW}Step 1/7: Building NixOS ISO from source...${NC}"
    echo -e "  ${CYAN}This may take a while. Grab a coffee!${NC}"
    echo ""

    if ! command -v nix &>/dev/null; then
        echo -e "${RED}Nix is not installed. It's needed to build from source.${NC}"
        echo -e "  Install it: ${CYAN}curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install${NC}"
        exit 1
    fi

    rm -f result
    nix build .#default --print-build-logs --verbose 2>&1 | tee /tmp/nix-build.log
    ISO_PATH=$(readlink -f result/iso/*.iso)
    echo -e "  ${GREEN}ISO built: $ISO_PATH${NC}"
fi

echo ""

# ── Step 2: Tor private key? ────────────────────────────────────────────────
# Non-interactive: SP_TOR_KEY=/path/to/key (empty or unset = generate new)
TOR_KEY_FILE="${SP_TOR_KEY:-}"
if [ -n "$TOR_KEY_FILE" ]; then
    if [ ! -f "$TOR_KEY_FILE" ]; then
        echo -e "${RED}SP_TOR_KEY file not found: $TOR_KEY_FILE${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}Using custom Tor key: $TOR_KEY_FILE${NC}"
elif [ -z "${SP_BUILD_MODE:-}" ]; then
    # Interactive mode — ask the user
    echo -e "${BOLD}Do you have an existing Tor private key to reuse?${NC}"
    echo -e "  (This lets you keep the same .onion address across reinstalls)"
    echo ""
    if ask_yn "  Use a custom Tor key?" "n"; then
        echo ""
        echo -e "  Enter the path to your ${CYAN}hs_ed25519_secret_key${NC} file:"
        read -r -p "  Path: " TOR_KEY_FILE
        if [ ! -f "$TOR_KEY_FILE" ]; then
            echo -e "${RED}File not found: $TOR_KEY_FILE${NC}"
            exit 1
        fi
        echo -e "  ${GREEN}Key will be installed after VM boots.${NC}"
    else
        echo -e "  ${GREEN}OK, a new .onion address will be generated.${NC}"
    fi
else
    echo -e "  ${GREEN}A new .onion address will be generated.${NC}"
fi
echo ""

# ── Step 3: Create VM ───────────────────────────────────────────────────────
echo -e "${YELLOW}Step 2/7: Creating VirtualBox VM...${NC}"
ssh-keygen -R '[localhost]:2222' 2>/dev/null || true

VBoxManage createvm --name "$VM_NAME" --ostype "Linux_64" --register

VM_CFG=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "^CfgFile=" | sed 's/CfgFile="//' | sed 's/"$//')
VM_DIR=$(dirname "$VM_CFG")

VBoxManage modifyvm "$VM_NAME" \
    --memory $VM_MEMORY \
    --cpus $VM_CPUS \
    --vram 32 \
    --graphicscontroller vmsvga \
    --nic1 nat \
    --natpf1 "ssh,tcp,,$SSH_PORT,,22" \
    --audio-enabled off \
    --boot1 dvd \
    --boot2 disk \
    --ioapic on

VBoxManage createmedium disk --filename "${VM_DIR}/${VM_NAME}.vdi" --size $VM_DISK_SIZE --format VDI
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "${VM_DIR}/${VM_NAME}.vdi"
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$ISO_PATH"

echo -e "  ${GREEN}VM created.${NC}"
echo ""

# ── Step 4: Boot from ISO ───────────────────────────────────────────────────
echo -e "${YELLOW}Step 3/7: Booting from ISO...${NC}"
VBoxManage startvm "$VM_NAME" --type headless

# ── Step 5: Wait for SSH ────────────────────────────────────────────────────
echo -e "${YELLOW}Step 4/7: Waiting for VM to boot...${NC}"
wait_for_ssh 180

# ── Step 6: Install NixOS ───────────────────────────────────────────────────
echo -e "${YELLOW}Step 5/7: Installing NixOS (this takes several minutes)...${NC}"
echo ""

sshpass -p '' ssh $SSH_OPTS -p $SSH_PORT root@localhost 'bash -s' << 'EOF'
set -e
echo "  >>> Partitioning disk..."
parted -s /dev/sda mklabel msdos
parted -s /dev/sda mkpart primary 1MiB 100%
echo "  >>> Formatting..."
mkfs.ext4 -F -L nixos /dev/sda1
sleep 2
udevadm settle 2>/dev/null || true
echo "  >>> Mounting..."
mount /dev/sda1 /mnt
echo "  >>> Installing NixOS (please wait)..."
nixos-install --flake /iso/selfprivacy-config#selfprivacy-tor-vm --no-root-passwd --no-channel-copy
echo "  >>> Done!"
EOF

echo -e "  ${GREEN}Installation complete!${NC}"
echo ""

# ── Step 7: Reboot into installed system ────────────────────────────────────
echo -e "${YELLOW}Step 6/7: Rebooting into installed system...${NC}"
VBoxManage controlvm "$VM_NAME" poweroff || true
sleep 3

VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --medium emptydrive
VBoxManage modifyvm "$VM_NAME" --boot1 disk --boot2 none
VBoxManage startvm "$VM_NAME" --type headless

wait_for_ssh 180

# ── Step 8: Install Tor key if provided ─────────────────────────────────────
if [ -n "$TOR_KEY_FILE" ]; then
    echo -e "${YELLOW}  Installing custom Tor private key...${NC}"
    do_ssh_cmd 'systemctl stop tor' 2>/dev/null
    sshpass -p '' scp $SSH_OPTS -P $SSH_PORT "$TOR_KEY_FILE" root@localhost:/var/lib/tor/hidden_service/hs_ed25519_secret_key 2>/dev/null
    do_ssh_cmd 'chown toranon:toranon /var/lib/tor/hidden_service/hs_ed25519_secret_key && chmod 600 /var/lib/tor/hidden_service/hs_ed25519_secret_key && rm -f /var/lib/tor/hidden_service/hs_ed25519_public_key /var/lib/tor/hidden_service/hostname && systemctl start tor' 2>/dev/null
    echo -e "  ${GREEN}Custom key installed.${NC}"
fi

# ── Step 9: Get .onion address ──────────────────────────────────────────────
echo -e "${YELLOW}Step 7/7: Waiting for Tor to publish your .onion address...${NC}"
wait_for_onion 120

if [ -z "$ONION" ]; then
    echo -e "${RED}Could not get .onion address. Tor may still be starting.${NC}"
    echo -e "  Try: ${CYAN}sshpass -p '' ssh -p $SSH_PORT root@localhost cat /var/lib/tor/hidden_service/hostname${NC}"
    exit 1
fi

print_success
