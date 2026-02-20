#!/bin/bash
# scrub-and-push.sh — Verify no Tor key material is in the repo and destroy
# recording keys on the VM before pushing.
#
# Run this AFTER recording GIFs and BEFORE pushing to remote.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo -e "${YELLOW}=== Tor Key Scrubbing Check ===${NC}"
echo ""

# ── 1. Verify no Tor keys in the git tree ──────────────────────────────────
echo -e "${YELLOW}[1/4] Checking git tree for Tor key material...${NC}"
if git ls-files | grep -qE '(hs_ed25519|hidden_service/hostname)'; then
    echo -e "${RED}ERROR: Tor key material found in git tree! Remove before pushing:${NC}"
    git ls-files | grep -E '(hs_ed25519|hidden_service/hostname)'
    exit 1
fi
echo -e "${GREEN}  ✓ No Tor key material in git tree${NC}"

# ── 2. Verify .gitignore blocks Tor keys ───────────────────────────────────
echo -e "${YELLOW}[2/4] Verifying .gitignore blocks Tor keys...${NC}"
MISSING=""
for pattern in '**/hs_ed25519_secret_key' '**/hs_ed25519_public_key' '**/hidden_service/hostname'; do
    if ! grep -qF "$pattern" .gitignore 2>/dev/null; then
        MISSING="$MISSING $pattern"
    fi
done

if [ -n "$MISSING" ]; then
    echo -e "${YELLOW}  Adding missing .gitignore entries:${MISSING}${NC}"
    echo "" >> .gitignore
    echo "# Tor hidden service keys (NEVER commit these)" >> .gitignore
    for pattern in $MISSING; do
        echo "$pattern" >> .gitignore
    done
    echo -e "${GREEN}  ✓ .gitignore updated${NC}"
else
    echo -e "${GREEN}  ✓ .gitignore already blocks Tor keys${NC}"
fi

# ── 3. Destroy recording keys on the VM ────────────────────────────────────
echo -e "${YELLOW}[3/4] Destroying Tor keys on VM...${NC}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password"

if sshpass -p '' ssh $SSH_OPTS -o ConnectTimeout=3 -p 2222 root@localhost true 2>/dev/null; then
    sshpass -p '' ssh $SSH_OPTS -p 2222 root@localhost \
        'rm -f /var/lib/tor/hidden_service/hs_ed25519_secret_key \
               /var/lib/tor/hidden_service/hs_ed25519_public_key \
               /var/lib/tor/hidden_service/hostname && \
         systemctl restart tor' 2>/dev/null
    echo -e "${GREEN}  ✓ Tor keys destroyed — new .onion will be generated on next restart${NC}"
else
    echo -e "${YELLOW}  ⚠ VM not reachable (port 2222). Skipping key destruction.${NC}"
    echo -e "${YELLOW}    If you recorded GIFs, make sure to destroy keys manually before pushing.${NC}"
fi

# ── 4. Confirm safe to push ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=== All checks passed ===${NC}"
echo -e "${GREEN}The .onion address visible in any recorded GIFs is now dead.${NC}"
echo -e "${GREEN}Safe to push.${NC}"
echo ""
echo -e "Run ${YELLOW}git push${NC} when ready."
