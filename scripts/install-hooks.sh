#!/bin/bash
# install-hooks.sh — Install git pre-commit hook to prevent pushing live .onion domains
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Installing pre-commit hook..."
cp "$SCRIPT_DIR/pre-commit-onion-check" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"
echo "Done. The hook will block commits containing a live .onion domain."
