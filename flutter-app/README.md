# SelfPrivacy Flutter App (Tor-Modified)

This is the SelfPrivacy Flutter app modified to work with Tor hidden services (.onion addresses).

For build instructions, prerequisites, and usage, see the [app README](selfprivacy.org.app/README.md).

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

### 6. `lib/main.dart`
- Runtime onion domain entry screen (no recompile needed when backend changes)
- Optional compile-time auto-setup via `--dart-define=ONION_DOMAIN=... --dart-define=API_TOKEN=...`
