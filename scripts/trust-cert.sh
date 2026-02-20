#!/usr/bin/env bash
# trust-cert.sh - Install/remove the SelfPrivacy .onion CA cert
# in the Ubuntu system CA store.
#
# Usage:
#   ./trust-cert.sh                   # Fetch from VM and install
#   ./trust-cert.sh /path/to/cert.pem # Install a specific cert file
#   ./trust-cert.sh --remove          # Remove from system CA store

set -euo pipefail

CERT_NAME="selfprivacy-tor-ca"
SYSTEM_CERT_DIR="/usr/local/share/ca-certificates"
SYSTEM_CERT_PATH="${SYSTEM_CERT_DIR}/${CERT_NAME}.crt"
VM_CERT_PATH="/etc/ssl/selfprivacy/cert.pem"

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

    if openssl x509 -in "${dest}" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
        echo "  CA:TRUE constraint: present"
    else
        echo "  WARNING: Certificate does not have CA:TRUE basic constraint."
        echo "  Regenerate the cert on the VM:"
        echo "    ssh root@VM 'rm /etc/ssl/selfprivacy/cert.pem /etc/ssl/selfprivacy/key.pem && systemctl restart selfprivacy-generate-ssl-cert nginx'"
    fi
}

install_cert() {
    local cert_file="$1"
    echo ""
    echo "Installing to system CA store..."
    sudo cp "${cert_file}" "${SYSTEM_CERT_PATH}"
    sudo update-ca-certificates
    echo ""
    echo "Done. Installed: ${SYSTEM_CERT_PATH}"
    echo "To remove: $0 --remove"
}

remove_cert() {
    echo "Removing ${CERT_NAME} from system CA store..."
    if [ -f "${SYSTEM_CERT_PATH}" ]; then
        sudo rm -f "${SYSTEM_CERT_PATH}"
        sudo update-ca-certificates --fresh
        echo "Removed: ${SYSTEM_CERT_PATH}"
    else
        echo "Not found in system CA store (already clean)"
    fi
}

main() {
    if [ "${1:-}" = "--remove" ]; then
        remove_cert
        exit 0
    fi

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

    install_cert "${cert_file}"

    if [ -n "${tmp_cert}" ]; then
        rm -f "${tmp_cert}"
    fi
}

main "$@"
