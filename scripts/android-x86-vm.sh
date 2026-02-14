#!/bin/bash
# android-x86-vm.sh — Create, boot, and configure an Android-x86 VirtualBox VM
# for testing .onion apps without KVM/Orbot.
#
# Usage:
#   ./scripts/android-x86-vm.sh create      — Download ISO, create VM, boot, run setup, take snapshot
#   ./scripts/android-x86-vm.sh start       — Start VM from "setup-complete" snapshot
#   ./scripts/android-x86-vm.sh stop        — Power off VM
#   ./scripts/android-x86-vm.sh adb         — Connect ADB to the running VM
#   ./scripts/android-x86-vm.sh setup-tor   — Set up Tor proxy + CA cert on running VM
#   ./scripts/android-x86-vm.sh destroy     — Delete VM and all files
#   ./scripts/android-x86-vm.sh status      — Show VM status
#
# Prerequisites: VirtualBox 7.1+, adb, wget/curl

set -uo pipefail
# Note: no 'set -e' — some VBoxManage/adb commands may fail non-fatally

VM_NAME="Android-x86-Test"
VM_DIR="$HOME/VirtualBox VMs/$VM_NAME"
ISO_URL="https://sourceforge.net/projects/android-x86/files/Release%209.0/android-x86_64-9.0-r2.iso/download"
ISO_PATH="$VM_DIR/android-x86.iso"
ADB_GUEST_PORT=5555
ADB_HOST_PORT=15555
SNAPSHOT_NAME="setup-complete"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helper: type text into VM via VBoxManage scancodes ──────────────────────

vbox_type() {
  local vm="$1" text="$2"
  declare -A SCAN=(
    [a]=1e [b]=30 [c]=2e [d]=20 [e]=12 [f]=21 [g]=22 [h]=23 [i]=17 [j]=24
    [k]=25 [l]=26 [m]=32 [n]=31 [o]=18 [p]=19 [q]=10 [r]=13 [s]=1f [t]=14
    [u]=16 [v]=2f [w]=11 [x]=2d [y]=15 [z]=2c
    [0]=0b [1]=02 [2]=03 [3]=04 [4]=05 [5]=06 [6]=07 [7]=08 [8]=09 [9]=0a
    [.]=34 [-]=0c [=]=0d [/]=35 [' ']=39 [\;]=27 [\']=28 [\,]=33 [\\]=2b
    [\[]=1a [\]]=1b [\`]=29
  )
  declare -A SHIFT_SCAN=(
    [A]=1e [B]=30 [C]=2e [D]=20 [E]=12 [F]=21 [G]=22 [H]=23 [I]=17 [J]=24
    [K]=25 [L]=26 [M]=32 [N]=31 [O]=18 [P]=19 [Q]=10 [R]=13 [S]=1f [T]=14
    [U]=16 [V]=2f [W]=11 [X]=2d [Y]=15 [Z]=2c
    [!]=02 [@]=03 [#]=04 [$]=05 [%]=06 [^]=07 [&]=08 [*]=09 [(]=0a [)]=0b
    [_]=0c [+]=0d [{]=1a [}]=1b [|]=2b [:]=27 [\"]=28 [<]=33 [>]=34 [?]=35
    [~]=29
  )
  local codes=""
  for (( i=0; i<${#text}; i++ )); do
    local c="${text:$i:1}"
    if [[ -n "${SCAN[$c]+x}" ]]; then
      local press="${SCAN[$c]}"
      local release
      release=$(printf '%02x' $((16#$press | 0x80)))
      codes+="$press $release "
    elif [[ -n "${SHIFT_SCAN[$c]+x}" ]]; then
      local press="${SHIFT_SCAN[$c]}"
      local release
      release=$(printf '%02x' $((16#$press | 0x80)))
      codes+="2a $press $release aa "
    fi
    local count
    count=$(echo "$codes" | wc -w)
    if [[ $count -ge 20 ]]; then
      VBoxManage controlvm "$vm" keyboardputscancode $codes 2>/dev/null
      codes=""
      sleep 0.05
    fi
  done
  if [[ -n "$codes" ]]; then
    VBoxManage controlvm "$vm" keyboardputscancode $codes 2>/dev/null
  fi
}

# Type a command into the Android console and press Enter
vbox_cmd() {
  vbox_type "$VM_NAME" "$1"
  sleep 0.2
  # Press Enter (scancode 1c down, 9c up)
  VBoxManage controlvm "$VM_NAME" keyboardputscancode 1c 9c 2>/dev/null
}

# Switch to text console (Ctrl+Alt+F1)
vbox_console() {
  VBoxManage controlvm "$VM_NAME" keyboardputscancode 1d 38 3b bb b8 9d 2>/dev/null
  sleep 1
}

# Switch to GUI (Ctrl+Alt+F7)
vbox_gui() {
  VBoxManage controlvm "$VM_NAME" keyboardputscancode 1d 38 41 c1 b8 9d 2>/dev/null
  sleep 1
}

# Run Android 'input tap x y' from the console
android_tap() {
  vbox_console
  sleep 0.5
  vbox_cmd "input tap $1 $2"
  sleep 1
  vbox_gui
}

# Connect ADB via NAT port forwarding
adb_connect() {
  local target="127.0.0.1:$ADB_HOST_PORT"
  adb disconnect "$target" 2>/dev/null || true
  sleep 1
  if adb connect "$target" 2>&1 | grep -q "connected"; then
    echo "  ADB connected to $target"
    adb -s "$target" shell getprop ro.build.version.release 2>/dev/null && echo ""
    return 0
  else
    echo "  ADB connection to $target failed."
    return 1
  fi
}

# ── Commands ────────────────────────────────────────────────────────────────

cmd_create() {
  echo "=== Creating Android-x86 VM ==="

  # Check prerequisites
  if ! command -v VBoxManage &>/dev/null; then
    echo "ERROR: VBoxManage not found. Install VirtualBox 7.1+." >&2
    exit 1
  fi

  # Check if VM already exists
  if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    echo "VM '$VM_NAME' already exists."
    read -rp "Delete and recreate? [y/N] " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
      VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
      sleep 2
      VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
      sleep 1
    else
      echo "Aborted." >&2
      exit 1
    fi
  fi

  # Download ISO if needed
  mkdir -p "$VM_DIR"
  if [[ ! -f "$ISO_PATH" ]]; then
    echo "Downloading Android-x86 9.0-r2 ISO (~920MB)..."
    wget -O "$ISO_PATH" "$ISO_URL" || curl -L -o "$ISO_PATH" "$ISO_URL"
  else
    echo "ISO already exists: $ISO_PATH"
  fi

  # Create VM with NAT NIC (for internet + ADB port forwarding).
  # Android's ConnectivityService validates the NAT network via DHCP,
  # which allows adbd to accept socket connections.
  # ADB connects through NAT port forwarding (host:15555 → guest:5555).
  echo "Creating VM..."
  VBoxManage createvm --name "$VM_NAME" --ostype Linux_64 --register
  VBoxManage modifyvm "$VM_NAME" \
    --memory 2048 --cpus 2 \
    --nic1 nat \
    --nat-pf1 "adb,tcp,,$ADB_HOST_PORT,,$ADB_GUEST_PORT" \
    --graphicscontroller vboxvga --vram 256 \
    --audio-driver none \
    --boot1 dvd --boot2 disk

  VBoxManage createmedium disk \
    --filename "$VM_DIR/$VM_NAME.vdi" \
    --size 8000

  VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAHCI
  VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 \
    --type hdd --medium "$VM_DIR/$VM_NAME.vdi"
  VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 \
    --type dvddrive --medium "$ISO_PATH"

  echo "VM created. Starting headless..."
  VBoxManage startvm "$VM_NAME" --type headless

  # GRUB auto-boots "Live CD" (first option) after 60s timeout.
  # Do NOT send Enter — it risks selecting Debug mode if timing is wrong.
  # Wait for GRUB timeout (60s) + Android boot (~150s without KVM).
  echo "Waiting for GRUB auto-boot (60s) + Android boot (~150s)..."
  sleep 210
  echo "  Boot wait complete."

  # Skip setup wizard from the console
  echo "Skipping setup wizard..."
  vbox_console
  sleep 1

  # Disable the setup wizard and mark device as provisioned
  vbox_cmd "pm disable com.google.android.setupwizard 2>/dev/null"
  sleep 2
  vbox_cmd "settings put global device_provisioned 1"
  sleep 1
  vbox_cmd "settings put secure user_setup_complete 1"
  sleep 1

  # Launch home screen
  vbox_cmd "am start -a android.intent.action.MAIN -c android.intent.category.HOME"
  sleep 3

  # If "Select a Home app" dialog appears, select Taskbar
  # Tap Taskbar option then ALWAYS
  vbox_cmd "input tap 375 628"
  sleep 1
  vbox_cmd "input tap 697 688"
  sleep 2

  # NAT NIC gets DHCP automatically from VBox NAT.
  # Wait for Android's ConnectivityService to validate the network.
  echo "Waiting for network validation..."
  sleep 15

  # Enable ADB over network
  echo "Enabling ADB over network..."
  vbox_cmd "setprop service.adb.tcp.port $ADB_GUEST_PORT"
  sleep 1
  vbox_cmd "setprop ro.adb.secure 0"
  sleep 1
  vbox_cmd "stop adbd"
  sleep 2
  vbox_cmd "start adbd"
  sleep 5

  # Connect ADB via NAT port forwarding
  echo "Connecting ADB..."
  adb_connect

  # Take snapshot
  echo "Taking snapshot '$SNAPSHOT_NAME'..."
  VBoxManage snapshot "$VM_NAME" take "$SNAPSHOT_NAME" \
    --description "Android-x86 with setup complete, ADB enabled, ready for app testing" \
    --live
  echo ""
  echo "=== Done! ==="
  echo "VM: $VM_NAME"
  echo "Snapshot: $SNAPSHOT_NAME"
  echo "ADB: adb connect 127.0.0.1:$ADB_HOST_PORT"
  echo ""
  echo "Next steps:"
  echo "  1. adb -s 127.0.0.1:$ADB_HOST_PORT shell  # verify ADB works"
  echo "  2. Install CA cert and apps"
}

cmd_start() {
  echo "=== Starting Android-x86 VM ==="

  if ! VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    echo "ERROR: VM '$VM_NAME' not found. Run './scripts/android-x86-vm.sh create' first." >&2
    exit 1
  fi

  # Check if already running
  if VBoxManage list runningvms 2>/dev/null | grep -q "$VM_NAME"; then
    echo "VM is already running."
    cmd_adb
    return
  fi

  # Restore snapshot if available — this resumes the VM state directly (no GRUB)
  if VBoxManage snapshot "$VM_NAME" list 2>/dev/null | grep -q "$SNAPSHOT_NAME"; then
    echo "Restoring snapshot '$SNAPSHOT_NAME'..."
    VBoxManage snapshot "$VM_NAME" restore "$SNAPSHOT_NAME"
    sleep 2
  fi

  echo "Starting VM headless..."
  VBoxManage startvm "$VM_NAME" --type headless

  # Snapshot resume is fast — just wait for network to come up
  echo "Waiting for VM to resume..."
  sleep 30

  cmd_adb
}

cmd_stop() {
  echo "=== Stopping Android-x86 VM ==="
  if VBoxManage list runningvms 2>/dev/null | grep -q "$VM_NAME"; then
    VBoxManage controlvm "$VM_NAME" poweroff
    echo "VM stopped."
  else
    echo "VM is not running."
  fi
}

cmd_adb() {
  echo "=== Connecting ADB ==="
  if ! VBoxManage list runningvms 2>/dev/null | grep -q "$VM_NAME"; then
    echo "ERROR: VM is not running. Start it first with: $0 start" >&2
    return 1
  fi
  adb_connect
}

cmd_setup_tor() {
  echo "=== Setting up Tor access on Android VM ==="

  local target="127.0.0.1:$ADB_HOST_PORT"
  if ! adb -s "$target" shell "echo ok" &>/dev/null; then
    echo "ERROR: ADB not connected. Run '$0 adb' first." >&2
    return 1
  fi

  # Forward host Tor HTTP tunnel port to Android localhost
  # Requires Tor running on host with HTTPTunnelPort 8118
  echo "Setting up adb reverse port forwarding..."
  adb -s "$target" reverse tcp:8118 tcp:8118
  adb -s "$target" reverse tcp:9050 tcp:9050

  # Set Android global HTTP proxy to use Tor HTTP tunnel
  echo "Configuring Android global HTTP proxy..."
  adb -s "$target" shell "settings put global http_proxy 127.0.0.1:8118"

  # Install CA cert if available
  local cert_path=""
  if [[ -f "$SCRIPT_DIR/../backend/cert.pem" ]]; then
    cert_path="$SCRIPT_DIR/../backend/cert.pem"
  elif sshpass -p '' scp -P 2222 -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    root@localhost:/etc/ssl/selfprivacy/cert.pem /tmp/sp-cert.pem 2>/dev/null; then
    cert_path="/tmp/sp-cert.pem"
  fi

  if [[ -n "$cert_path" ]]; then
    echo "Pushing CA cert to Android..."
    adb -s "$target" push "$cert_path" /data/local/tmp/selfprivacy-ca.crt 2>/dev/null
    adb -s "$target" shell "cp /data/local/tmp/selfprivacy-ca.crt /sdcard/Download/selfprivacy-ca.crt" 2>/dev/null
    echo ""
    echo "  Cert pushed to /sdcard/Download/selfprivacy-ca.crt"
    echo "  To install: Settings → Security → Encryption & credentials → Install from SD card"
    echo "  (A PIN/pattern must be set first)"
  fi

  # Get .onion address
  local onion=""
  onion=$(sshpass -p '' ssh -p 2222 -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    root@localhost "cat /var/lib/tor/hidden_service/hostname" 2>/dev/null)

  echo ""
  echo "=== Tor setup complete ==="
  echo "Global proxy: 127.0.0.1:8118 (Tor HTTP tunnel)"
  echo "adb reverse: tcp:8118→8118, tcp:9050→9050"
  if [[ -n "$onion" ]]; then
    echo ".onion: $onion"
    echo ""
    echo "Test in Chrome: https://$onion/"
  fi
}

cmd_destroy() {
  echo "=== Destroying Android-x86 VM ==="
  read -rp "This will delete the VM and all data. Continue? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy] ]]; then
    echo "Aborted."
    exit 0
  fi
  VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
  sleep 2
  VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
  # Clean up remaining files
  rm -rf "$VM_DIR"
  echo "VM destroyed."
}

cmd_status() {
  echo "=== Android-x86 VM Status ==="
  if ! VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    echo "VM not found. Run './scripts/android-x86-vm.sh create' first."
    return
  fi
  local state
  state=$(VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep "^VMState=" | cut -d'"' -f2)
  echo "VM: $VM_NAME"
  echo "State: $state"
  echo "ADB port forwarding: host:$ADB_HOST_PORT → guest:$ADB_GUEST_PORT"

  if VBoxManage snapshot "$VM_NAME" list 2>/dev/null | grep -q "$SNAPSHOT_NAME"; then
    echo "Snapshot: $SNAPSHOT_NAME (available)"
  else
    echo "Snapshot: none"
  fi

  if [[ "$state" == "running" ]]; then
    echo ""
    echo "ADB: adb connect 127.0.0.1:$ADB_HOST_PORT"
  fi
}

# ── Main ────────────────────────────────────────────────────────────────────

case "${1:-help}" in
  create)    cmd_create ;;
  start)     cmd_start ;;
  stop)      cmd_stop ;;
  adb)       cmd_adb ;;
  setup-tor) cmd_setup_tor ;;
  destroy)   cmd_destroy ;;
  status)    cmd_status ;;
  *)
    echo "Usage: $0 {create|start|stop|adb|setup-tor|destroy|status}"
    echo ""
    echo "Commands:"
    echo "  create      Download ISO, create VM, complete setup, take snapshot"
    echo "  start       Start VM from snapshot (or boot fresh)"
    echo "  stop        Power off VM"
    echo "  adb         Connect ADB to running VM"
    echo "  setup-tor   Set up Tor proxy + CA cert on running VM"
    echo "  destroy     Delete VM and all files"
    echo "  status      Show VM state and ADB connectivity"
    exit 1
    ;;
esac
