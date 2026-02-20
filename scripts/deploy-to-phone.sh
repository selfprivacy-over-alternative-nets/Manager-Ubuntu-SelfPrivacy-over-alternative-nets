#!/usr/bin/env bash
# Build the Flutter APK, install on a connected Android device,
# launch the app, fill in the Tor setup screen, and navigate to Services.
#
# Usage:
#   ./scripts/deploy-to-phone.sh                        # default domain + token
#   ./scripts/deploy-to-phone.sh my.onion               # custom domain
#   ./scripts/deploy-to-phone.sh my.onion my-token      # custom domain + token
#   ./scripts/deploy-to-phone.sh --skip-build           # skip build, just install+launch
#   ./scripts/deploy-to-phone.sh --skip-build my.onion  # skip build, custom domain

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/../flutter-app/selfprivacy.org.app"
APK="$APP_DIR/build/app/outputs/flutter-apk/app-production-debug.apk"
PKG="org.selfprivacy.app"

SKIP_BUILD=false
if [ "${1:-}" = "--skip-build" ]; then
    SKIP_BUILD=true
    shift
fi

DOMAIN="${1:-eoqgqunffbxm6eryux3lrci3b3k3kl3ieazsv54yzisbhhzm6wd6xyid.onion}"
TOKEN="${2:-test-token-for-tor-development}"

# --- Check device ---
echo "==> Checking for connected device..."
if ! adb devices | grep -q "device$"; then
    echo "ERROR: No Android device connected. Connect via USB and enable USB debugging."
    exit 1
fi
DEVICE=$(adb devices | grep "device$" | head -1 | cut -f1)
echo "    Device: $DEVICE"

# --- Build ---
if [ "$SKIP_BUILD" = false ]; then
    echo "==> Building APK..."
    cd "$APP_DIR"
    flutter build apk --flavor production --debug 2>&1 | tail -3
    echo "    APK: $APK"
else
    echo "==> Skipping build (--skip-build)"
    if [ ! -f "$APK" ]; then
        echo "ERROR: No APK found at $APK. Run without --skip-build first."
        exit 1
    fi
fi

# --- Install ---
echo "==> Installing APK..."
adb install -r "$APK"

# --- Clear data & launch ---
echo "==> Clearing app data..."
adb shell pm clear "$PKG"

echo "==> Launching app..."
adb shell am start -n "$PKG/$PKG.MainActivity"

# Wait for setup screen to fully render (autofocus on domain field)
echo "==> Waiting for setup screen (6s)..."
sleep 6

# --- Fill setup screen ---
# Domain field has autofocus, keyboard should be up
echo "==> Entering domain: $DOMAIN"
adb shell input text "$DOMAIN"
sleep 1

echo "==> Tabbing to token field..."
adb shell input keyevent KEYCODE_TAB
sleep 0.5

# Token field has default value "test-token-for-tor-development".
# Clear and enter custom token if a different one was provided.
if [ "$TOKEN" != "test-token-for-tor-development" ]; then
    echo "==> Entering custom token..."
    adb shell input keyevent --longpress KEYCODE_CTRL_LEFT KEYCODE_A
    adb shell input text "$TOKEN"
    sleep 0.5
fi

# Dismiss keyboard with BACK so Tab can reach the buttons
echo "==> Dismissing keyboard (BACK)..."
adb shell input keyevent KEYCODE_BACK
sleep 1

# Now focus should be on the token field with keyboard gone.
# Tab: token -> Skip -> Connect (2 tabs to reach Connect, then activate)
echo "==> Tabbing to Connect button..."
adb shell input keyevent KEYCODE_TAB
sleep 0.3
adb shell input keyevent KEYCODE_TAB
sleep 0.3

echo "==> Pressing Connect (DPAD_CENTER)..."
adb shell input keyevent KEYCODE_DPAD_CENTER

echo "==> Waiting for app to connect over Tor (20s)..."
sleep 20

# --- Navigate to Services tab ---
echo "==> Looking for Services tab..."
adb shell uiautomator dump /sdcard/ui_deploy.xml 2>/dev/null || true
SERVICES_BOUNDS=$(adb shell cat /sdcard/ui_deploy.xml 2>/dev/null \
    | tr '>' '\n' \
    | grep 'content-desc="Services' \
    | sed 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/' \
    || true)

if [ -n "$SERVICES_BOUNDS" ]; then
    read -r X1 Y1 X2 Y2 <<< "$SERVICES_BOUNDS"
    CX=$(( (X1 + X2) / 2 ))
    CY=$(( (Y1 + Y2) / 2 ))
    adb shell input tap "$CX" "$CY"
    echo "    Tapped Services at ($CX, $CY)"
else
    echo "    WARNING: Could not find Services tab. App may still be connecting."
    echo "    Try tapping Services manually once the dashboard loads."
fi

echo ""
echo "==> Done! Check the device screen."
