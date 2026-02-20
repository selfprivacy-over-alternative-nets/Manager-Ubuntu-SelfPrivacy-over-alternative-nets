# SelfPrivacy over Tor

Run SelfPrivacy services (Nextcloud, Gitea, Jitsi, Prometheus) as Tor hidden services on a local VirtualBox VM.

## Quick Start

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt install virtualbox sshpass tor

# Clone and run
git clone --recursive https://github.com/selfprivacy-over-tor/Manager-Ubuntu-SelfPrivacy-Over-Tor.git
cd Manager-Ubuntu-SelfPrivacy-Over-Tor/backend
./build-and-run.sh
```

The script handles everything: downloads (or builds) the NixOS image, creates a VM, installs it, starts Tor, and prints all the credentials you need:

```
╔══════════════════════════════════════════════════════════════╗
║              SelfPrivacy Tor VM is ready!                   ║
╚══════════════════════════════════════════════════════════════╝

  .onion address:    abc...xyz.onion
  API token:         test-token-for-tor-development

  Nextcloud:
    URL:       https://abc...xyz.onion/nextcloud/
    Username:  admin
    Password:  <generated>

  Services:
    SelfPrivacy API  https://abc...xyz.onion/api/
    Nextcloud        https://abc...xyz.onion/nextcloud/
    Gitea            https://abc...xyz.onion/git/
    Jitsi Meet       https://abc...xyz.onion/jitsi/
    Prometheus       https://abc...xyz.onion/prometheus/

  SSH:
    sshpass -p '' ssh -p 2222 root@localhost

  Watch live requests:
    sshpass -p '' ssh -p 2222 root@localhost journalctl -u nginx -u selfprivacy-api -f

  Record demo GIFs:
    ./scripts/record-gif1.sh  (backend setup)
    ./scripts/record-gif2.sh  (Linux desktop app)
    ./scripts/record-gif3.sh  (Android VM app)
```

Re-running `./build-and-run.sh` on an existing VM gives you options to restart, generate a new `.onion` address, or do a clean reinstall.

## Demos

### SelfPrivacy App (Android) over Tor

![SelfPrivacy App Tor Demo](demo/selfprivacy-app-tor-demo.gif)

### Nextcloud App (Android) over Tor HTTPS

![Nextcloud App Tor Demo](demo/nextcloud-app-tor-demo.gif)

### Backend Setup via Script

Download prebuilt image, boot VM, get `.onion` address:

![Setup Tor Demo](demo/setup-tor-demo.gif)

Build from source, boot VM, get `.onion` address:

![Setup Tor Demo Build](demo/setup-tor-demo-build.gif)

### SelfPrivacy App (Linux Desktop) over Tor

![Linux App Tor Demo](demo/linux-app-tor-demo.gif)

### SelfPrivacy App (Android x86 VM) over Tor

![Android VM Tor Demo](demo/android-vm-tor-demo.gif)

## Running the Flutter App

### Linux Desktop

```bash
# Ensure Tor is running on the host (port 9050)
sudo systemctl start tor

# Build and run
cd flutter-app/selfprivacy.org.app
flutter pub get
flutter run -d linux
```

Enter your `.onion` address and API token in the setup screen.

### Android

```bash
cd flutter-app/selfprivacy.org.app
flutter build apk --flavor production --debug
adb install build/app/outputs/flutter-apk/app-production-debug.apk
```

Requires [Orbot](https://guardianproject.info/apps/org.torproject.android/) for Tor connectivity on the device.

## Recording Demo GIFs

All three GIF scripts are fully automated end-to-end. They require a running backend VM and Tor on the host.

```bash
# Record all demos (from the repo root):
./scripts/record-gif1.sh    # Terminal recording of backend setup
./scripts/record-gif2.sh    # Screen capture of Linux Flutter app
./scripts/record-gif3.sh    # Screen capture of Android x86 VM app

# After recording, scrub Tor keys before pushing:
./scripts/scrub-and-push.sh
```

Dependencies auto-installed by the scripts: `asciinema`, `agg`, `xvfb`, `ffmpeg`, `gifsicle`, `xdotool`.

## Non-interactive Mode

For CI/CD and scripts, `build-and-run.sh` supports environment variables to skip all prompts:

```bash
# Download prebuilt image, fresh install, no custom key:
SP_BUILD_MODE=download SP_VM_ACTION=reinstall ./build-and-run.sh

# Build from source:
SP_BUILD_MODE=build SP_VM_ACTION=reinstall ./build-and-run.sh

# Use a custom Tor key (persistent .onion address):
SP_BUILD_MODE=build SP_TOR_KEY=/path/to/hs_ed25519_secret_key ./build-and-run.sh
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      HOST MACHINE                           │
│                                                             │
│  ┌──────────────────┐     ┌─────────────────────────────┐  │
│  │   Flutter App    │     │      Tor SOCKS Proxy        │  │
│  │  (Linux/Android) │────>│      (port 9050)            │  │
│  └──────────────────┘     └──────────────┬──────────────┘  │
│                                          │                  │
└──────────────────────────────────────────│──────────────────┘
                                           │
                              Tor Network (encrypted)
                                           │
┌──────────────────────────────────────────│──────────────────┐
│                    VIRTUALBOX VM         │                   │
│                                         v                   │
│  ┌──────────────────┐     ┌─────────────────────────────┐  │
│  │  SelfPrivacy API │<────│     Tor Hidden Service      │  │
│  │   (port 5050)    │     │  (.onion:443 -> Nginx:443)  │  │
│  └────────┬─────────┘     └─────────────────────────────┘  │
│           │                                                 │
│  ┌────────v─────────┐     ┌─────────────────────────────┐  │
│  │      Redis       │     │      Nginx (TLS)            │  │
│  │  (token storage) │     │  /api/ /nextcloud/ /git/    │  │
│  └──────────────────┘     └─────────────────────────────┘  │
│                                                             │
│                      NixOS System                           │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting

```bash
# VM not running?
VBoxManage list runningvms

# Tor not started on VM?
sshpass -p '' ssh -p 2222 root@localhost systemctl status tor

# API not responding?
sshpass -p '' ssh -p 2222 root@localhost curl http://127.0.0.1:5050/api/version

# Test .onion from host (needs Tor on host):
curl --socks5-hostname 127.0.0.1:9050 -k https://YOUR_ONION.onion/api/version

# API logs:
sshpass -p '' ssh -p 2222 root@localhost journalctl -u selfprivacy-api -f

# Nginx logs:
sshpass -p '' ssh -p 2222 root@localhost journalctl -u nginx -f
```

## Repository Structure

```
├── backend/
│   ├── build-and-run.sh     # THE setup script — does everything
│   ├── flake.nix            # NixOS configuration with all services
│   └── flake.lock           # Pinned dependencies
├── flutter-app/
│   └── selfprivacy.org.app/ # Flutter app (submodule)
├── scripts/
│   ├── record-gif1.sh       # Record backend setup GIF
│   ├── record-gif2.sh       # Record Linux app GIF
│   ├── record-gif3.sh       # Record Android VM GIF
│   ├── scrub-and-push.sh    # Destroy Tor keys before pushing
│   ├── trust-cert.sh        # Trust self-signed cert (Ubuntu)
│   └── trust-cert-android.sh
└── demo/                    # GIF demos
```

## Security

The `.onion` address visible in demo GIFs becomes dead after recording. The `scrub-and-push.sh` script:

1. Verifies no Tor key material is in the git tree
2. Verifies `.gitignore` blocks `hs_ed25519_*` and `hidden_service/hostname`
3. Destroys the Tor keys on the VM (generates a new `.onion` on next restart)

Always run `./scripts/scrub-and-push.sh` before pushing after recording demos.
