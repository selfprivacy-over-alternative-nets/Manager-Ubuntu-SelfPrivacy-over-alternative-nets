# SelfPrivacy over Tor - Complete Collection

This repository contains everything needed to run SelfPrivacy over Tor hidden services (.onion addresses).

## Repository Structure

```
new_collection/
├── README.md                 # This file
├── backend/                  # NixOS backend for VirtualBox
│   ├── README.md            # Detailed backend instructions
│   ├── flake.nix            # NixOS configuration with Tor
│   ├── flake.lock           # Pinned dependencies
│   └── build-and-run.sh     # Automatic deployment script
└── flutter-app/             # Modified Flutter app
    └── selfprivacy.org.app/ # Full Flutter source code (with README)
```

## Demos

### SelfPrivacy App (Android) over Tor

The SelfPrivacy Flutter app connects to the backend over Tor, showing the dashboard, services (Forgejo, Jitsi, Matrix, Nextcloud), and user management:

![SelfPrivacy App Tor Demo](demo/selfprivacy-app-tor-demo.gif)

### Nextcloud App (Android) over Tor HTTPS

The Nextcloud Android app connecting to a .onion HTTPS backend, trusting the self-signed certificate, and successfully logging in:

![Nextcloud App Tor Demo](demo/nextcloud-app-tor-demo.gif)

## Quick Start

### Prerequisites (Ubuntu/Debian)

```bash
# Install build dependencies
sudo apt install ninja-build clang cmake pkg-config git curl \
  libgtk-3-dev libsecret-1-dev libjsoncpp-dev libblkid-dev \
  liblzma-dev xdg-user-dirs gnome-keyring unzip xz-utils zip \
  sshpass openjdk-21-jdk

# Install Flutter to /opt (NOT snap - snap causes GLib version conflicts)
curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.2-stable.tar.xz | sudo tar xJf - -C /opt
echo 'export PATH="/opt/flutter/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# Install Android SDK (for Android builds)
# Option A: Install Android Studio from https://developer.android.com/studio
# Option B: Command-line only:
mkdir -p ~/Android/Sdk && cd ~/Android/Sdk
curl -sL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o cmdline-tools.zip
unzip cmdline-tools.zip && mkdir -p cmdline-tools && mv cmdline-tools cmdline-tools/latest
export ANDROID_HOME=~/Android/Sdk
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platforms;android-35" "build-tools;36.1.0" "platform-tools"
flutter config --android-sdk ~/Android/Sdk

# Install Tor daemon (for .onion connectivity)
sudo apt install tor
sudo systemctl enable --now tor

# Verify Tor is running on port 9050
ss -tlnp | grep 9050

# For Android emulator: enable KVM
sudo modprobe kvm && sudo modprobe kvm_intel && sudo chmod 666 /dev/kvm
```

**Requirements:**
1. **Ubuntu/Linux host** with VirtualBox installed
2. **Nix package manager** with flakes enabled
3. **Flutter SDK** (3.32.2+) for building the app
4. **Android SDK** for Android APK builds
5. **Tor** for SOCKS5 proxy

### Updating the Flutter App Submodule (ONCE at start of clone)

To ensure the Flutter app refers to the latest commit of the main branch:

```bash
git submodule update --init --recursive --remote
```
This fetches the latest changes from the `main` branch of the [SelfPrivacy-Flutter-Ubuntu-and-Android-App-Over-Alternative-Nets](https://github.com/selfprivacy-over-alternative-nets/SelfPrivacy-Flutter-Ubuntu-and-Android-App-Over-Alternative-Nets) repository.

### Updating Flutter App submodule after commit
Each time you push commits to the SelfPrivacy-Flutter-Ubuntu-and-Android-App-Over-Alternative-Nets repo, in this Manager-Ubuntu-SelfPrivacy-Over-Alternative-Nets repo get that latest commit with:
```sh
cd /home/a/git/git/selfprivacy/Manager-Ubuntu-SelfPrivacy-Over-Alternative-Nets
git add flutter-app/selfprivacy.org.app
git commit -m "Update flutter-app submodule to latest"
git push
```

### Step 1: Deploy Backend (VirtualBox)

```bash
cd backend
./build-and-run.sh 2>&1 | tee /tmp/backend.log
```

Wait for the .onion address to be displayed (may take a few minutes for Tor to bootstrap).

### Step 2: Start Tor Proxy on Host

```bash
# Create minimal Tor config
cat > /tmp/user-torrc << 'EOF'
SocksPort 9050
Log notice stdout
EOF

# Start Tor
tor -f /tmp/user-torrc &
```

### Step 3: Trust the Self-Signed Certificate (Optional)

The backend uses a self-signed TLS certificate for HTTPS. The SelfPrivacy Flutter
app already accepts it, but other apps (Nextcloud, browsers, curl) will show
security warnings unless you install the certificate as a trusted CA.

**Ubuntu (system CA store):**
```bash
# Install (fetches cert from VM automatically)
./scripts/trust-cert.sh

# Or manually:
sshpass -p '' scp -P 2222 root@localhost:/etc/ssl/selfprivacy/cert.pem /tmp/sp-cert.pem
sudo cp /tmp/sp-cert.pem /usr/local/share/ca-certificates/selfprivacy-tor-ca.crt
sudo update-ca-certificates

# Verify (should work without -k):
curl --socks5-hostname 127.0.0.1:9050 https://YOUR_ONION.onion/api/version

# Remove:
sudo rm /usr/local/share/ca-certificates/selfprivacy-tor-ca.crt
sudo update-ca-certificates --fresh
```

**Android:**
```bash
# Push cert to device (fetches from VM automatically)
./scripts/trust-cert-android.sh

# Or manually:
sshpass -p '' scp -P 2222 root@localhost:/etc/ssl/selfprivacy/cert.pem /tmp/sp-cert.pem
openssl x509 -in /tmp/sp-cert.pem -outform DER -out /tmp/selfprivacy-tor-ca.crt
adb push /tmp/selfprivacy-tor-ca.crt /sdcard/Download/

# Then on the device:
#   Settings > Security > Encryption & credentials
#   > Install a certificate > CA certificate > Install anyway
#   > Select selfprivacy-tor-ca.crt from Downloads
#
# To remove:
#   Settings > Security > Encryption & credentials
#   > Trusted credentials > User tab > selfprivacy-tor > Remove
```

**What trusts the cert after installation:**

| Platform | Trusts system/user CA | Does NOT trust (use web instead) |
|----------|----------------------|----------------------------------|
| Ubuntu | curl, wget, Python, Dart/Flutter, Java | Chrome, Brave, Firefox (own cert stores) |
| Android | Nextcloud, Chrome | Jitsi Meet, Element |

### Step 4: Run Flutter App (Linux Desktop)

```bash
cd flutter-app/selfprivacy.org.app
rm -rf ~/.local/share/selfprivacy/*.hive ~/.local/share/selfprivacy/*.lock
flutter pub get
flutter run -d linux --verbose 2>&1 | tee /tmp/app.log
```

### Step 4 (Alternative): Build and Run Android APK

See [flutter-app/selfprivacy.org.app/README.md](flutter-app/selfprivacy.org.app/README.md#building-and-running-android-apk) for full Android build, emulator, and device installation instructions.

### Step 5: Connect

1. In the app, choose "I already have a server"
2. Enter your .onion address (from Step 1)
3. Enter the recovery key mnemonic

---

## Detailed Instructions

| Task | Documentation |
|------|---------------|
| A. Automatic backend deployment | [backend/README.md](backend/README.md#a-automatic-deployment-one-command) |
| B. Manual backend installation | [backend/README.md](backend/README.md#b-manual-deployment-steps) |
| C. Backend log inspection | [backend/README.md](backend/README.md#c-viewing-backend-logs) |
| D. Linux desktop app with logs | [flutter-app/selfprivacy.org.app/README.md](flutter-app/selfprivacy.org.app/README.md#running-the-linux-desktop-app) |
| E. Android APK build | [flutter-app/selfprivacy.org.app/README.md](flutter-app/selfprivacy.org.app/README.md#building-and-running-android-apk) |

---

## Log Commands Reference

### Backend Logs (in VirtualBox VM)

```bash
# API requests
sshpass -p '' ssh -p 2222 root@localhost journalctl -u selfprivacy-api -f

# Nginx access logs
sshpass -p '' ssh -p 2222 root@localhost journalctl -u nginx -f

# Combined
sshpass -p '' ssh -p 2222 root@localhost journalctl -u nginx -u selfprivacy-api -f
```

### Flutter App Logs (on host)

```bash
# Run with verbose logging
cd flutter-app/selfprivacy.org.app
flutter run -d linux --verbose 2>&1 | tee /tmp/flutter-app.log

# Search logs
grep "GraphQL Response" /tmp/flutter-app.log
grep -i error /tmp/flutter-app.log
```

### Android App Logs

```bash
adb logcat | grep -i selfprivacy
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      HOST MACHINE                            │
│                                                              │
│  ┌──────────────────┐     ┌─────────────────────────────┐   │
│  │   Flutter App    │     │      Tor SOCKS Proxy        │   │
│  │  (Linux/Android) │────▶│      (port 9050)            │   │
│  └──────────────────┘     └──────────────┬──────────────┘   │
│                                          │                   │
└──────────────────────────────────────────│───────────────────┘
                                           │
                              Tor Network (encrypted)
                                           │
┌──────────────────────────────────────────│───────────────────┐
│                    VIRTUALBOX VM          │                   │
│                                          ▼                   │
│  ┌──────────────────┐     ┌─────────────────────────────┐   │
│  │  SelfPrivacy API │◀────│     Tor Hidden Service      │   │
│  │   (port 5050)    │     │  (xxx.onion:443 → :443/TLS) │   │
│  └────────┬─────────┘     └─────────────────────────────┘   │
│           │                                                  │
│  ┌────────▼─────────┐     ┌─────────────────────────────┐   │
│  │      Redis       │     │         Nginx               │   │
│  │  (token storage) │     │  (reverse proxy + TLS)      │   │
│  └──────────────────┘     └─────────────────────────────┘   │
│                                                              │
│                      NixOS System                            │
└──────────────────────────────────────────────────────────────┘
```

---

## Recovery Key

The backend generates recovery tokens stored in Redis. To get the recovery key:

```bash
# SSH into VM
sshpass -p '' ssh -p 2222 root@localhost

# The key is stored as a BIP39 mnemonic (18 words)
# Check Redis for existing tokens:
redis-cli -s /run/redis-sp-api/redis.sock KEYS '*token*'
```

**Important:** The recovery key must be entered as a **BIP39 mnemonic phrase** (18 words), not as a hex string.

---

## Modifications Summary

### Backend (No modifications needed)
The upstream SelfPrivacy API works as-is. Tor handles all network routing externally.

### Flutter App (Modified for Tor)
| File | Change |
|------|--------|
| `graphql_api_map.dart` | SOCKS5 proxy for .onion |
| `rest_api_map.dart` | SOCKS5 proxy for .onion |
| `server_installation_repository.dart` | Skip DNS lookup, skip provider checks |
| `server_installation_cubit.dart` | Auto-complete recovery for .onion |
| `server_installation_state.dart` | Handle null DNS token |

---

## Troubleshooting

### Backend not accessible
```bash
# Check VM is running — good: shows "SelfPrivacy-Tor-Test", bad: empty output
VBoxManage list runningvms

# Check Tor service — good: "Active: active (running)", bad: "inactive" or "failed"
sshpass -p '' ssh -p 2222 root@localhost systemctl status tor

# Test API locally in VM — good: {"version":"3.x.x"}, bad: "Connection refused"
sshpass -p '' ssh -p 2222 root@localhost curl http://127.0.0.1:5050/api/version
```

### App can't connect
```bash
# Verify host Tor proxy — good: {"IsTor":true,...}, bad: "Connection refused" (Tor not running on host)
curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip

# Test .onion from host — good: {"version":"3.x.x"}, bad: "Connection refused" or timeout (hidden service not published yet, wait a few minutes)
curl --socks5-hostname 127.0.0.1:9050 -k https://YOUR_ONION.onion/api/version
```

### Recovery key rejected
- Must be 18-word BIP39 mnemonic
- Type manually if copy/paste fails
- Check backend logs for auth errors

---

## VM Management

```bash
# Start
VBoxManage startvm "SelfPrivacy-Tor-Test" --type headless

# Stop
VBoxManage controlvm "SelfPrivacy-Tor-Test" poweroff

# SSH
sshpass -p '' ssh -p 2222 root@localhost

# Get .onion address
sshpass -p '' ssh -p 2222 root@localhost cat /var/lib/tor/hidden_service/hostname

# Delete VM
VBoxManage unregistervm "SelfPrivacy-Tor-Test" --delete

# Nextcloud
username=`admin`

sshpass -p '' ssh -p 2222 -o StrictHostKeyChecking=no root@localhost 'cat /var/lib/nextcloud/admin-pass'
```
