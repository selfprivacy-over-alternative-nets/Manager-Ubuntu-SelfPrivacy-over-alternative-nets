# Minimal NixOS module for SelfPrivacy Tor backend.
# Used by the Manager's nixosConfigurations AND exported as nixosModules.default
# so the selfprivacy-tor-tests nixosTest can import it directly.
#
# Provides:
#   - selfprivacy-api + huey worker + redis
#   - Tor hidden service (port 443)
#   - Self-signed TLS cert (generated after HS hostname is known)
#   - nginx with path-based routing for all Tor-accessible services
#
# Does NOT include full service stacks (Nextcloud, Gitea, Matrix, etc.).
# Those remain in the Manager's main flake.nix for the production VM.
#
# Required module arg (pass via specialArgs or _module.args):
#   selfprivacy-api-package — the selfprivacy-graphql-api Python package derivation

{ config, pkgs, lib, selfprivacy-api-package, ... }:

let
  redis-sp-api-srv-name = "sp-api";
  selfprivacy-graphql-api = selfprivacy-api-package;
  workerPython = pkgs.python312.withPackages (ps: [
    selfprivacy-graphql-api
    ps.huey
  ]);
in
{
  time.timeZone = "UTC";

  # ── Tor hidden service ───────────────────────────────────────────────────
  services.tor = {
    enable = true;
    settings = {
      HiddenServiceDir = "/var/lib/tor/hidden_service";
      HiddenServicePort = [ "443 127.0.0.1:443" ];
    };
  };

  # ── Redis ────────────────────────────────────────────────────────────────
  services.redis.package = pkgs.valkey;
  services.redis.servers.${redis-sp-api-srv-name} = {
    enable = true;
    save = [
      [ 30 1 ]
      [ 10 10 ]
    ];
    port = 0;
    settings.notify-keyspace-events = "KEA";
  };

  # ── Users ────────────────────────────────────────────────────────────────
  users.users.selfprivacy-api = {
    isSystemUser = true;
    group = "selfprivacy-api";
  };
  users.groups.selfprivacy-api = { };
  users.groups.redis-sp-api.members = [ "selfprivacy-api" "root" ];

  # ── SelfPrivacy API ──────────────────────────────────────────────────────
  systemd.services.selfprivacy-api = {
    description = "SelfPrivacy GraphQL API";
    after = [ "network-online.target" "redis-${redis-sp-api-srv-name}.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOME = "/root";
      PYTHONUNBUFFERED = "1";
    };
    path = with pkgs; [
      coreutils
      gnutar
      xz.bin
      gzip
      gitMinimal
      iproute2
      util-linux
    ];
    serviceConfig = {
      User = "root";
      ExecStart = "${selfprivacy-graphql-api}/bin/app.py";
      Restart = "always";
      RestartSec = "5";
    };
  };

  systemd.services.selfprivacy-api-worker = {
    description = "SelfPrivacy API Task Worker";
    after = [ "network-online.target" "redis-${redis-sp-api-srv-name}.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOME = "/root";
      PYTHONUNBUFFERED = "1";
    };
    path = with pkgs; [
      coreutils
      gnutar
      xz.bin
      gzip
      gitMinimal
      iproute2
      util-linux
    ];
    serviceConfig = {
      User = "root";
      ExecStart = "${workerPython}/bin/python -m huey.bin.huey_consumer selfprivacy_api.task_registry.huey";
      Restart = "always";
      RestartSec = "5";
    };
  };

  # ── TLS cert (self-signed, SAN = actual .onion hostname) ────────────────
  systemd.services.selfprivacy-generate-ssl-cert = {
    description = "Generate self-signed TLS certificate for .onion HTTPS";
    wantedBy = [ "multi-user.target" ];
    after = [ "tor.service" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl pkgs.coreutils ];
    script = ''
      CERT_DIR="/etc/ssl/selfprivacy"
      HOSTNAME_FILE="/var/lib/tor/hidden_service/hostname"
      mkdir -p "$CERT_DIR"

      for i in $(seq 1 60); do
        [ -f "$HOSTNAME_FILE" ] && break
        sleep 1
      done

      ONION_HOST=""
      if [ -f "$HOSTNAME_FILE" ]; then
        ONION_HOST=$(cat "$HOSTNAME_FILE" | tr -d '[:space:]')
        echo "Onion hostname: $ONION_HOST"
      else
        echo "WARNING: Tor hostname not found, using wildcard SAN"
      fi

      NEED_REGEN=false
      if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
        NEED_REGEN=true
      elif [ -n "$ONION_HOST" ]; then
        if ! openssl x509 -in "$CERT_DIR/cert.pem" -noout -text 2>/dev/null | grep -q "$ONION_HOST"; then
          echo "Cert SAN does not match current onion hostname, regenerating"
          NEED_REGEN=true
        fi
      fi

      if [ "$NEED_REGEN" = true ]; then
        SAN="DNS:*.onion"
        [ -n "$ONION_HOST" ] && SAN="DNS:$ONION_HOST,DNS:*.onion"

        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
          -days 397 -nodes \
          -keyout "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/cert.pem" \
          -subj "/CN=selfprivacy-tor" \
          -addext "subjectAltName=$SAN" \
          -addext "basicConstraints=critical,CA:TRUE"
        chown root:nginx "$CERT_DIR/key.pem"
        chmod 640 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        echo "Generated TLS certificate with SAN=$SAN"
      else
        echo "TLS certificate already valid"
      fi
    '';
  };

  # ── nginx path-based routing ─────────────────────────────────────────────
  services.nginx = {
    enable = true;

    virtualHosts."onion" = {
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      default = true;
      onlySSL = true;
      sslCertificate = "/etc/ssl/selfprivacy/cert.pem";
      sslCertificateKey = "/etc/ssl/selfprivacy/key.pem";

      locations."/graphql" = {
        proxyPass = "http://127.0.0.1:5050";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };

      locations."/api" = {
        proxyPass = "http://127.0.0.1:5050";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
        '';
      };

      locations."/prometheus" = {
        proxyPass = "http://127.0.0.1:9001";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
        '';
      };

      locations."/prometheus/api" = {
        proxyPass = "http://127.0.0.1:9001/api";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
        '';
      };

      locations."/nextcloud/" = {
        proxyPass = "http://127.0.0.1:8081/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
          proxy_redirect off;
          client_max_body_size 512M;
        '';
      };
      locations."= /nextcloud" = { return = "301 /nextcloud/"; };

      locations."/git/" = {
        proxyPass = "http://127.0.0.1:3000/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
        '';
      };
      locations."= /git" = { return = "301 /git/"; };

      locations."/_matrix" = {
        proxyPass = "http://127.0.0.1:8008";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
          client_max_body_size 50M;
        '';
      };

      locations."/jitsi/" = {
        proxyPass = "http://127.0.0.1:9090/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
        '';
      };
    };
  };

  systemd.services.nginx.after = [ "selfprivacy-generate-ssl-cert.service" ];
  systemd.services.nginx.wants = [ "selfprivacy-generate-ssl-cert.service" ];

  # ── Firewall: allow SSH and HTTPS only (Tor handles external access) ─────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 443 ];
  };

  environment.systemPackages = with pkgs; [
    curl
    htop
    vim
    tor
    jq
    openssl
    python3
    valkey
  ];
}
