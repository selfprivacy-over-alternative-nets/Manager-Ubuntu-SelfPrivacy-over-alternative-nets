# Manager-Ubuntu-SelfPrivacy-Over-Tor — notes for Claude

Runs SelfPrivacy services as Tor hidden services (and over HTTPS) and connects the SelfPrivacy app to them; `README.md`
explains the setups.

- `backend/` — the test VM: `backend/build-and-run.sh` (VirtualBox; `SP_VM_MEMORY` sets its RAM, default 4096 MiB —
  `nixos-install` builds the whole system in the live ISO's RAM) and the NixOS modules in `backend/nixos/`.
- `flutter-app/selfprivacy.org.app/` — the app, a submodule with its own repo. Linux desktop build and the L3 tests:
  `nix develop .#linux` in that folder (one nixpkgs for the Flutter engine, GTK and the toolchain).
- `scripts/` — helpers; `get_virtualbox.sh` installs VirtualBox 7.1 on Ubuntu 24.04 (noble).

The work's context — handovers, decisions, Claude's memory — is in the private repo `selfprivacy-context`, cloned next to
this one. This repo is **public**: never commit IP addresses, onion addresses, tokens, passwords or your domain; check
with `python3 ../selfprivacy-context/tools/scan_sensitive.py --deny /home/a/selfprivacy-private/redaction-map.txt <files>`.
Commands in docs are written in full, every argument explicit.
