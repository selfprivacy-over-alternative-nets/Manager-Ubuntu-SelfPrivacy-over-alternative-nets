#!/bin/bash
# build-and-run.sh — Single entry point for SelfPrivacy over Tor
#
# Usage:
#   ./build-and-run.sh                  # Setup backend VM (interactive)
#   ./build-and-run.sh --info           # Print credentials for running VM
#   ./build-and-run.sh --app-linux      # Build & launch SelfPrivacy app on Linux
#   ./build-and-run.sh --record-gif-app-linux  # Record demo GIF of Linux app
#   ./build-and-run.sh --app-android    # Build & deploy app to Android device
#   ./build-and-run.sh --trust-cert     # Trust VM cert on Ubuntu
#   ./build-and-run.sh --trust-cert-android  # Push VM cert to Android device
#   ./build-and-run.sh --proxy              # Local reverse proxy to .onion (browse at localhost)
#   ./build-and-run.sh --status             # Check VM, Tor, and all services
#   ./build-and-run.sh --get-onion-private-key  # Export Tor key (base64)
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
        FLUTTER_DIR="$SCRIPT_DIR/../flutter-app/selfprivacy.org.app"
        if ! command -v flutter &>/dev/null; then
            echo -e "${RED}Flutter SDK not found. Run: ${CYAN}./scripts/requirements.sh --app-linux${NC}" >&2
            exit 1
        fi
        echo -e "${YELLOW}Building Flutter Linux app...${NC}"
        echo -e "  .onion: ${CYAN}$ONION${NC}"
        cd "$FLUTTER_DIR"
        flutter pub get --no-example 2>/dev/null
        flutter build linux --debug \
            --dart-define=ONION_DOMAIN="$ONION" \
            --dart-define=API_TOKEN=test-token-for-tor-development \
            2>&1 | tail -5
        BINARY="build/linux/x64/debug/bundle/selfprivacy"
        if [ ! -f "$BINARY" ]; then
            echo -e "${RED}Build failed — binary not found.${NC}" >&2
            exit 1
        fi
        echo -e "${GREEN}Build complete. Launching...${NC}"
        rm -rf ~/.local/share/selfprivacy/*.hive ~/.local/share/selfprivacy/*.lock 2>/dev/null || true
        exec "$BINARY"
        ;;
    --record-gif-app-linux)
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
    --proxy)
        require_vm
        LOCAL_PORT="${2:-8443}"

        # Kill any existing proxy on this port (clean slate)
        EXISTING_PID=$(lsof -ti :"$LOCAL_PORT" 2>/dev/null || true)
        if [ -n "$EXISTING_PID" ]; then
            echo -e "  ${YELLOW}Killing existing proxy on port $LOCAL_PORT (PID $EXISTING_PID)...${NC}"
            kill $EXISTING_PID 2>/dev/null || true
            sleep 1
        fi

        # Verify Tor is running on host
        if ! ss -tlnp 2>/dev/null | grep -q ':9050 '; then
            echo -e "${RED}Tor is not running on host port 9050.${NC}"
            echo -e "  ${CYAN}sudo systemctl start tor${NC}"
            exit 1
        fi

        # Fresh cert from current VM state
        CERT_DIR=$(mktemp -d)
        trap "rm -rf $CERT_DIR" EXIT
        do_ssh_cmd cat /etc/ssl/selfprivacy/cert.pem > "$CERT_DIR/cert.pem" 2>/dev/null
        do_ssh_cmd cat /etc/ssl/selfprivacy/key.pem > "$CERT_DIR/key.pem" 2>/dev/null

        # If we couldn't get the VM's cert, generate a throwaway self-signed one
        if [ ! -s "$CERT_DIR/cert.pem" ] || [ ! -s "$CERT_DIR/key.pem" ]; then
            echo -e "  ${YELLOW}Could not fetch VM cert, generating local self-signed cert...${NC}"
            openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/key.pem" \
                -out "$CERT_DIR/cert.pem" -days 30 -nodes \
                -subj "/CN=localhost" 2>/dev/null
        fi

        # Quick sanity check: can we reach the .onion?
        echo -e "  ${YELLOW}Verifying Tor connectivity to $ONION...${NC}"
        VERIFY_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
            --socks5-hostname 127.0.0.1:9050 \
            -k "https://$ONION/api/version" 2>/dev/null) || true
        VERIFY_CODE="${VERIFY_CODE:-000}"
        if [ "$VERIFY_CODE" = "000" ]; then
            echo -e "  ${RED}Cannot reach .onion over Tor. Is the VM fully booted?${NC}"
            echo -e "  Try: ${CYAN}./build-and-run.sh --status${NC}"
            exit 1
        fi
        echo -e "  ${GREEN}Tor connectivity OK${NC}"

        echo ""
        echo -e "${GREEN}Starting local reverse proxy to .onion services via Tor${NC}"
        echo ""
        echo -e "  .onion:  ${CYAN}$ONION${NC}"
        echo -e "  Proxy:   ${CYAN}https://localhost:$LOCAL_PORT${NC}"
        echo ""
        echo -e "  ${BOLD}Open in your browser:${NC}"
        echo -e "    Nextcloud   ${CYAN}https://localhost:$LOCAL_PORT/nextcloud/${NC}"
        echo -e "    Gitea       ${CYAN}https://localhost:$LOCAL_PORT/git/${NC}"
        echo -e "    Jitsi       ${CYAN}https://localhost:$LOCAL_PORT/jitsi/${NC}"
        echo -e "    Prometheus  ${CYAN}https://localhost:$LOCAL_PORT/prometheus/${NC}"
        echo -e "    API         ${CYAN}https://localhost:$LOCAL_PORT/api/version${NC}"
        echo ""
        echo -e "  ${YELLOW}Accept the self-signed certificate warning in Firefox to proceed.${NC}"
        echo -e "  ${YELLOW}Press Ctrl+C to stop.${NC}"
        echo ""

        python3 -u - "$ONION" "$LOCAL_PORT" "$CERT_DIR/cert.pem" "$CERT_DIR/key.pem" <<'PYEOF'
import sys, ssl, http.server
import requests

ONION = sys.argv[1]
PORT = int(sys.argv[2])
CERTFILE = sys.argv[3]
KEYFILE = sys.argv[4]
LOCAL_ORIGIN = f"https://localhost:{PORT}"
ONION_ORIGIN = f"https://{ONION}"

session = requests.Session()
session.proxies = {"https": "socks5h://127.0.0.1:9050", "http": "socks5h://127.0.0.1:9050"}
session.verify = False

# Suppress InsecureRequestWarning
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

HOP_HEADERS = frozenset(["transfer-encoding", "connection", "keep-alive",
                          "te", "trailers", "upgrade", "content-encoding"])

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_request(self):
        url = f"{ONION_ORIGIN}{self.path}"
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in ("host",)}
        headers["Host"] = ONION

        body = None
        length = self.headers.get("Content-Length")
        if length:
            body = self.rfile.read(int(length))

        try:
            resp = session.request(self.command, url, headers=headers,
                                   data=body, allow_redirects=False,
                                   timeout=60, stream=True)
        except Exception as e:
            self.send_error(502, f"Proxy error: {e}")
            return

        self.send_response_only(resp.status_code)
        data = resp.content

        for k, v in resp.headers.items():
            if k.lower() in HOP_HEADERS or k.lower() == "content-length":
                continue
            if k.lower() == "location":
                v = v.replace(ONION_ORIGIN, LOCAL_ORIGIN)
                v = v.replace(f"http://{ONION}", LOCAL_ORIGIN)
            self.send_header(k, v)

        # Rewrite .onion references in response body
        data = data.replace(ONION_ORIGIN.encode(), LOCAL_ORIGIN.encode())
        data = data.replace(ONION.encode(), f"localhost:{PORT}".encode())
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = do_request
    do_PROPFIND = do_PROPPATCH = do_MKCOL = do_COPY = do_MOVE = do_LOCK = do_UNLOCK = do_REPORT = do_request

    def log_message(self, fmt, *args):
        sys.stderr.write(f"  {args[0]}\n")
        sys.stderr.flush()

server = http.server.HTTPServer(("127.0.0.1", PORT), ProxyHandler)
server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_ctx.load_cert_chain(CERTFILE, KEYFILE)
server.socket = server_ctx.wrap_socket(server.socket, server_side=True)
print(f"  Listening on https://127.0.0.1:{PORT} -> {ONION}:443 via Tor")

try:
    server.serve_forever()
except KeyboardInterrupt:
    print("\n  Proxy stopped.")
    server.server_close()
PYEOF
        ;;
    --status)
        echo ""
        echo -e "${BOLD}SelfPrivacy Tor VM — Status Check${NC}"
        echo ""

        # 1. VM running?
        if sshpass -p '' ssh -n $SSH_OPTS -o ConnectTimeout=3 -p $SSH_PORT root@localhost true 2>/dev/null; then
            echo -e "  ${GREEN}[ok]${NC} VM reachable via SSH (port $SSH_PORT)"
        else
            echo -e "  ${RED}[fail]${NC} VM not reachable via SSH (port $SSH_PORT)"
            echo ""
            echo -e "  Run ${CYAN}./build-and-run.sh${NC} to start it."
            exit 1
        fi

        # 2. Tor running on VM?
        ONION=$(do_ssh_cmd cat /var/lib/tor/hidden_service/hostname 2>/dev/null || true)
        if [ -n "$ONION" ]; then
            echo -e "  ${GREEN}[ok]${NC} Tor hidden service configured (${CYAN}$ONION${NC})"
        else
            echo -e "  ${RED}[fail]${NC} Tor hidden service not configured on VM"
            exit 1
        fi

        # 3. Tor SOCKS proxy on host?
        if ss -tlnp 2>/dev/null | grep -q ':9050 '; then
            echo -e "  ${GREEN}[ok]${NC} Tor SOCKS proxy running on host (port 9050)"
        else
            echo -e "  ${RED}[fail]${NC} Tor SOCKS proxy not running on host (port 9050)"
            echo -e "       Run: ${CYAN}sudo systemctl start tor${NC}"
            exit 1
        fi

        # 4. Test services over Tor
        echo ""
        echo -e "  ${BOLD}Services over Tor:${NC}"

        check_tor_url() {
            local name="$1" path="$2"
            local code
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
                --socks5-hostname 127.0.0.1:9050 \
                -k "https://$ONION$path" 2>/dev/null) || true
            code="${code:-000}"
            if [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 400 ] 2>/dev/null; then
                echo -e "  ${GREEN}[ok]${NC} $name (HTTP $code)"
            elif [ "$code" = "000" ]; then
                echo -e "  ${RED}[fail]${NC} $name (timeout/unreachable)"
            else
                echo -e "  ${YELLOW}[${code}]${NC} $name"
            fi
        }

        check_tor_url "SelfPrivacy API" "/api/version"
        check_tor_url "Nextcloud"       "/nextcloud/"
        check_tor_url "Gitea"           "/git/"
        check_tor_url "Jitsi Meet"      "/jitsi/"
        check_tor_url "Prometheus"      "/prometheus/"

        echo ""
        exit 0
        ;;
    --get-onion-private-key)
        require_vm
        echo -e "${BOLD}.onion address:${NC} ${CYAN}$ONION${NC}"
        echo ""
        echo -e "${BOLD}Base64-encoded private key (for KeePass):${NC}"
        do_ssh_cmd base64 -w0 /var/lib/tor/hidden_service/hs_ed25519_secret_key 2>/dev/null
        echo ""
        echo ""
        echo -e "${BOLD}To restore later:${NC}"
        echo -e "  ${CYAN}echo 'BASE64_STRING' | base64 -d > /tmp/hs_ed25519_secret_key${NC}"
        echo -e "  ${CYAN}SP_TOR_KEY=/tmp/hs_ed25519_secret_key ./build-and-run.sh${NC}"
        exit 0
        ;;
    --help|-h)
        echo "Usage: ./build-and-run.sh [COMMAND]"
        echo ""
        echo "Commands:"
        echo "  (none)               Setup backend VM (interactive)"
        echo "  --info               Print credentials for running VM"
        echo "  --app-linux          Build & launch SelfPrivacy app on Linux desktop"
        echo "  --app-android        Build & deploy SelfPrivacy app to Android device"
        echo "  --trust-cert         Trust the VM's self-signed cert on Ubuntu"
        echo "  --trust-cert-android Push the VM's cert to Android device"
        echo "  --proxy [PORT]       Local reverse proxy (default 8443) — browse .onion at localhost"
        echo "  --status             Check VM, Tor, and all services"
        echo "  --get-onion-private-key  Export Tor private key (base64, for KeePass)"
        echo "  --record-gif-app-linux   Record demo GIF of Linux app setup"
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
bash "$SCRIPT_DIR/../scripts/requirements.sh" --check 2>/dev/null
MISSING=""
if ! command -v VBoxManage &>/dev/null; then MISSING="$MISSING virtualbox"; fi
if ! command -v sshpass &>/dev/null; then MISSING="$MISSING sshpass"; fi

if [ -n "$MISSING" ]; then
    echo -e "${RED}Missing:${MISSING}${NC}"
    echo ""
    echo -e "  Run: ${CYAN}./scripts/requirements.sh${NC}"
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

# Re-run domain services so all configs (userdata.json, Nextcloud) use the correct .onion
echo -e "${YELLOW}  Updating service configs with .onion address...${NC}"
do_ssh_cmd 'systemctl restart selfprivacy-set-onion-domain.service' 2>/dev/null || true
do_ssh_cmd 'systemctl restart nextcloud-set-onion-host.service' 2>/dev/null || true
echo -e "  ${GREEN}Done.${NC}"

print_success
