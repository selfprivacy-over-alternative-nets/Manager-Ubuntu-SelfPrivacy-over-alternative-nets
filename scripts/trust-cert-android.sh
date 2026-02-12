#!/usr/bin/env bash
# trust-cert-android.sh - Push the SelfPrivacy .onion CA cert
# to a connected Android device for trust store installation.
#
# Usage:
#   ./trust-cert-android.sh                   # Fetch from VM and push
#   ./trust-cert-android.sh /path/to/cert.pem # Push a specific cert
#   ./trust-cert-android.sh --remove          # Remove cert file from device

set -euo pipefail

CERT_NAME="selfprivacy-tor-ca"
ANDROID_DEST="/sdcard/Download/${CERT_NAME}.crt"
VM_CERT_PATH="/etc/ssl/selfprivacy/cert.pem"

check_device() {
    if ! command -v adb &>/dev/null; then
        echo "ERROR: adb not found. Install Android platform-tools."
        exit 1
    fi
    if ! adb devices | grep -q "device$"; then
        echo "ERROR: No Android device connected."
        echo "Connect via USB and enable USB debugging."
        exit 1
    fi
    local device
    device=$(adb devices | grep "device$" | head -1 | cut -f1)
    echo "Connected device: ${device}"
}

fetch_cert() {
    local dest="$1"
    echo "Fetching certificate from VM..."
    sshpass -p '' scp -P 2222 -o StrictHostKeyChecking=no root@localhost:"${VM_CERT_PATH}" "${dest}"

    if ! openssl x509 -in "${dest}" -noout 2>/dev/null; then
        echo "ERROR: Downloaded file is not a valid X.509 certificate"
        rm -f "${dest}"
        exit 1
    fi

    echo "  Subject: $(openssl x509 -in "${dest}" -noout -subject 2>/dev/null)"
    echo "  Expires: $(openssl x509 -in "${dest}" -noout -enddate 2>/dev/null)"
}

push_cert() {
    local pem_file="$1"

    echo ""
    echo "Converting to DER format for Android..."
    local der_file
    der_file="$(mktemp /tmp/selfprivacy-cert-XXXXXX.der)"
    openssl x509 -in "${pem_file}" -outform DER -out "${der_file}"

    echo "Pushing certificate to Android device..."
    adb push "${der_file}" "${ANDROID_DEST}"
    rm -f "${der_file}"

    echo ""
    echo "Certificate pushed to: ${ANDROID_DEST}"
    echo ""
    echo "To install as a trusted CA on the device:"
    echo "  1. Settings > Security > Encryption & credentials"
    echo "  2. Tap 'Install a certificate' > 'CA certificate'"
    echo "  3. Tap 'Install anyway'"
    echo "  4. Select '${CERT_NAME}.crt' from Downloads"
    echo ""
    echo "After installation, Nextcloud Android will trust the cert."
    echo "Jitsi Meet Android does NOT trust user CAs (use web instead)."
    echo ""
    echo "To remove: $0 --remove"
}

remove_cert() {
    check_device
    echo "Removing certificate file from Android device..."
    adb shell rm -f "${ANDROID_DEST}" 2>/dev/null || true
    echo "Removed: ${ANDROID_DEST}"
    echo ""
    echo "To remove the installed CA from the Android trust store:"
    echo "  1. Settings > Security > Encryption & credentials"
    echo "  2. Tap 'Trusted credentials' > 'User' tab"
    echo "  3. Find 'selfprivacy-tor' and tap 'Remove'"
}

main() {
    if [ "${1:-}" = "--remove" ]; then
        remove_cert
        exit 0
    fi

    check_device

    local cert_file=""
    local tmp_cert=""

    if [ -n "${1:-}" ] && [ -f "${1:-}" ]; then
        cert_file="$1"
        echo "Using provided certificate: ${cert_file}"
    else
        tmp_cert="$(mktemp /tmp/selfprivacy-cert-XXXXXX.pem)"
        fetch_cert "${tmp_cert}"
        cert_file="${tmp_cert}"
    fi

    push_cert "${cert_file}"

    if [ -n "${tmp_cert}" ]; then
        rm -f "${tmp_cert}"
    fi
}

main "$@"
