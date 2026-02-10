# SelfPrivacy Flutter App (Tor-Modified)

This is the SelfPrivacy Flutter app modified to work with Tor hidden services (.onion addresses).

## Modifications Made for Tor Support

The following files were modified to enable .onion domain connectivity:

### 1. `lib/logic/api_maps/graphql_maps/graphql_api_map.dart`
- Routes .onion requests through SOCKS5 proxy (port 9050)
- Disables TLS certificate verification for .onion (Tor provides encryption)

### 2. `lib/logic/api_maps/rest_maps/rest_api_map.dart`
- Same SOCKS5 proxy routing for REST API calls

### 3. `lib/logic/cubit/server_installation/server_installation_repository.dart`
- Skips DNS lookup for .onion domains (Tor handles routing internally)
- Skips provider token requirements for .onion domains

### 4. `lib/logic/cubit/server_installation/server_installation_cubit.dart`
- Auto-completes recovery flow for .onion domains (skips Hetzner/Backblaze prompts)

### 5. `lib/logic/cubit/server_installation/server_installation_state.dart`
- Handles null DNS API token for .onion domains

## Prerequisites

### For Linux Desktop

```bash
# Install Flutter
# See: https://docs.flutter.dev/get-started/install/linux

# Install Linux desktop dependencies (Ubuntu/Debian)
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev

# Install and start Tor SOCKS proxy
sudo apt-get install tor
```

### For Android

```bash
# Install Android SDK
# Option A: Install Android Studio from https://developer.android.com/studio
# Option B: Command-line only:
mkdir -p ~/Android/Sdk && cd ~/Android/Sdk
curl -sL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o cmdline-tools.zip
unzip cmdline-tools.zip && mkdir -p cmdline-tools && mv cmdline-tools cmdline-tools/latest
export ANDROID_HOME=~/Android/Sdk
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platforms;android-35" "build-tools;36.1.0" "platform-tools"
flutter config --android-sdk ~/Android/Sdk

# For Android emulator: enable KVM (required for usable speed)
sudo modprobe kvm && sudo modprobe kvm_intel && sudo chmod 666 /dev/kvm
```

## D. Running the Linux Desktop App (With Logs)

### Step 1: Start Tor SOCKS Proxy on Host

```bash
# Option 1: Use system Tor
sudo systemctl start tor

# Option 2: Run Tor with custom config
cat > /tmp/user-torrc << 'EOF'
SocksPort 9050
Log notice stdout
EOF
tor -f /tmp/user-torrc &
```

Verify Tor is running:
```bash
curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
```

### Step 2: Run Flutter App with Logs

```bash
cd selfprivacy.org.app
flutter pub get
flutter run -d linux --verbose 2>&1 | tee /tmp/flutter-app.log
```

### Step 3: Connect to Backend

In the app:
1. Choose "I already have a server" (recovery flow)
2. Enter your .onion address: `YOUR_ONION_ADDRESS.onion`
3. Enter recovery key (18-word BIP39 mnemonic)

**Note:** Copy/paste may not work in Flutter Linux desktop. Type manually if needed.

### Viewing Logs

```bash
# Live logs during runtime (verbose)
# Already shown in terminal if using command above

# Or tail the log file
tail -f /tmp/flutter-app.log

# Search for GraphQL responses
grep "GraphQL Response" /tmp/flutter-app.log

# Search for errors
grep -i error /tmp/flutter-app.log
```

## E. Building and Running Android APK

The Android app is built from the same Flutter source code with the `production` flavor.

### Build Debug APK

```bash
cd selfprivacy.org.app
flutter pub get

# Get .onion address from your VM
ONION=$(sshpass -p '' ssh -p 2222 root@localhost cat /var/lib/tor/hidden_service/hostname)

# Build debug APK with auto-setup (skips onboarding, connects to your .onion)
flutter build apk --flavor production --debug \
  --dart-define=ONION_DOMAIN=$ONION \
  --dart-define=API_TOKEN=test-token-for-tor-development

# APK is at: build/app/outputs/flutter-apk/app-production-debug.apk
```

### Install on Android Emulator

```bash
# Enable KVM first (required for usable emulator speed)
sudo modprobe kvm && sudo modprobe kvm_intel && sudo chmod 666 /dev/kvm

# Start emulator (create one in Android Studio first, or use avdmanager)
export ANDROID_HOME=~/Android/Sdk
$ANDROID_HOME/emulator/emulator -avd Medium_Phone_API_36.1 -no-audio &

# Wait for boot, then install
$ANDROID_HOME/platform-tools/adb wait-for-device
$ANDROID_HOME/platform-tools/adb install build/app/outputs/flutter-apk/app-production-debug.apk
```

### Install on Physical Android Device

1. Install [Orbot](https://play.google.com/store/apps/details?id=org.torproject.android) (Tor proxy for Android)
2. Enable "VPN mode" in Orbot to route all traffic through Tor
3. Transfer the APK to the device and install it
4. Open the app — it will auto-connect to your .onion backend

**Note:** On Android, services opened via "Open in Browser" require a Tor-capable browser (e.g., Tor Browser for Android) or Orbot in VPN mode routing the default browser through Tor.

### Android Logs

```bash
# View Flutter and SelfPrivacy logs
adb logcat -s flutter,SelfPrivacy

# View all app logs (verbose)
adb logcat | grep -i selfprivacy
```

### Build Flavors

The app has multiple build flavors:
- `production` - Production release (recommended for Tor builds)
- `fdroid` - F-Droid release (different application ID)
- `nightly` - Development builds

## Troubleshooting

### "Connection refused" or timeout
- Ensure Tor SOCKS proxy is running on port 9050
- Check: `curl --socks5-hostname 127.0.0.1:9050 http://YOUR_ONION.onion/api/version`

### "Invalid recovery key"
- The key must be a 18-word BIP39 mnemonic phrase, NOT a hex string
- Example format: `word1 word2 word3 ... word18`

### DNS lookup errors
- Should not happen with .onion domains (they skip DNS lookup)
- If it does, verify the modifications in `server_installation_repository.dart`

### Copy/paste not working (Linux)
- Known Flutter Linux desktop bug
- Type the recovery key manually

### GraphQL errors in logs
- Check backend logs to see if request arrived
- Verify .onion address is correct
- Ensure backend API is running: `curl --socks5-hostname 127.0.0.1:9050 http://YOUR_ONION.onion/graphql`
