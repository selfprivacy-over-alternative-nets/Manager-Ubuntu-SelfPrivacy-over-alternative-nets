#!/usr/bin/env bash
# Fill in the SelfPrivacy Tor Setup screen on a connected Android device.
# Usage: ./adb-setup-app.sh [onion-domain] [api-token]

set -euo pipefail

DOMAIN="${1:-eoqgqunffbxm6eryux3lrci3b3k3kl3ieazsv54yzisbhhzm6wd6xyid.onion}"
TOKEN="${2:-test-token-for-tor-development}"

echo "Launching SelfPrivacy app..."
adb shell am start -n org.selfprivacy.app/org.selfprivacy.app.MainActivity
sleep 3

echo "Typing onion domain: $DOMAIN"
adb shell input text "$DOMAIN"
sleep 1

echo "Tabbing to API Token field..."
adb shell input keyevent KEYCODE_TAB
sleep 0.5

# Token is pre-filled by default. Clear and re-enter if a custom token was given.
if [ "$TOKEN" != "test-token-for-tor-development" ]; then
    echo "Clearing default token and entering: $TOKEN"
    adb shell input keyevent KEYCODE_CTRL_LEFT KEYCODE_A
    adb shell input text "$TOKEN"
    sleep 0.5
fi

echo "Tabbing to Connect button (3 tabs)..."
adb shell input keyevent KEYCODE_TAB
sleep 0.3
adb shell input keyevent KEYCODE_TAB
sleep 0.3
adb shell input keyevent KEYCODE_TAB
sleep 0.3

echo "Pressing Connect..."
adb shell input keyevent KEYCODE_DPAD_CENTER
sleep 2

echo "Done. Check the device screen."
