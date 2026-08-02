# Minimal NixOS module for SelfPrivacy public HTTPS backend.
# Used by the Manager's nixosConfigurations AND exported as nixosModules.https
# so the selfprivacy-tor-tests nixosTest can import it directly.
#
# Provides:
#   - selfprivacy-api + huey worker + redis
#   - Self-signed TLS certificate (SAN = domain + *.domain)
#   - nginx with subdomain-based routing (api.domain, cloud.domain, git.domain, …)
#   - Ports 80 (ACME HTTP-01 challenge) + 443 (HTTPS)
#
# Does NOT include full service stacks (Nextcloud, Gitea, Matrix, etc.).
# Those remain in the Manager's main flake.nix for the production VM.
#
# For production: replace the self-signed cert by adding security.acme to your
# NixOS configuration and setting useACMEHost on the nginx virtual hosts.
# See: https://nixos.org/manual/nixos/stable/index.html#module-security-acme
#
# Required module args (pass via specialArgs or _module.args):
#   selfprivacy-api-package — selfprivacy-graphql-api Python package derivation
#   selfprivacy-domain      — the public domain, e.g. "example.com"

{ config, pkgs, lib, selfprivacy-api-package, selfprivacy-domain, ... }:

let
  redis-sp-api-srv-name = "sp-api";
  selfprivacy-graphql-api = selfprivacy-api-package;
  domain = selfprivacy-domain;

  workerPython = pkgs.python312.withPackages (ps: [
    selfprivacy-graphql-api
    ps.huey
  ]);

  certDir = "/etc/ssl/selfprivacy-https";
  certFile = "${certDir}/cert.pem";
  keyFile  = "${certDir}/key.pem";

  commonProxyHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  '';
in
{
  time.timeZone = "UTC";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
      nix
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

  # ── TLS certificate ──────────────────────────────────────────────────────
  # Development/test: self-signed cert with proper SANs.
  # Production: overlay with security.acme + useACMEHost in the VirtualHosts below.
  systemd.services.selfprivacy-generate-https-cert = {
    description = "Generate self-signed TLS certificate for HTTPS";
    wantedBy = [ "multi-user.target" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl pkgs.coreutils ];
    script = ''
      CERT_DIR="${certDir}"
      mkdir -p "$CERT_DIR"

      if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
        SAN="DNS:${domain},DNS:*.${domain}"
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
          -days 397 -nodes \
          -keyout "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/cert.pem" \
          -subj "/CN=${domain}" \
          -addext "subjectAltName=$SAN" \
          -addext "basicConstraints=critical,CA:TRUE"
        chown root:nginx "$CERT_DIR/key.pem"
        chmod 640 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        echo "Generated self-signed TLS certificate for ${domain} (dev/test mode)"
        echo "For production, use security.acme and set useACMEHost on virtual hosts."
      else
        echo "TLS certificate already present"
      fi
    '';
  };

  # ── nginx subdomain-based routing ────────────────────────────────────────
  # Matches the URL scheme produced by selfprivacy-api's get_url() for
  # non-.onion domains: https://{subdomain}.{domain}
  services.nginx = {
    enable = true;

    # api.${domain} — GraphQL and REST API endpoints
    virtualHosts."api.${domain}" = {
      onlySSL = true;
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      sslCertificate = certFile;
      sslCertificateKey = keyFile;

      locations."/graphql" = {
        proxyPass = "http://127.0.0.1:5050";
        extraConfig = commonProxyHeaders;
      };

      locations."/api" = {
        proxyPass = "http://127.0.0.1:5050";
        extraConfig = commonProxyHeaders;
      };
    };

    # cloud.${domain} — Nextcloud (when service stack is enabled)
    virtualHosts."cloud.${domain}" = {
      onlySSL = true;
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      sslCertificate = certFile;
      sslCertificateKey = keyFile;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8081";
        extraConfig = ''
          ${commonProxyHeaders}
          client_max_body_size 512M;
        '';
      };
    };

    # git.${domain} — Forgejo/Gitea
    virtualHosts."git.${domain}" = {
      onlySSL = true;
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      sslCertificate = certFile;
      sslCertificateKey = keyFile;

      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        extraConfig = commonProxyHeaders;
      };
    };

    # matrix.${domain} — Matrix Synapse client/federation API
    virtualHosts."matrix.${domain}" = {
      onlySSL = true;
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      sslCertificate = certFile;
      sslCertificateKey = keyFile;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8008";
        extraConfig = ''
          ${commonProxyHeaders}
          client_max_body_size 50M;
        '';
      };
    };

    # meet.${domain} — Jitsi Meet
    virtualHosts."meet.${domain}" = {
      onlySSL = true;
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      sslCertificate = certFile;
      sslCertificateKey = keyFile;

      locations."/" = {
        proxyPass = "http://127.0.0.1:9090";
        extraConfig = commonProxyHeaders;
      };
    };
  };

  systemd.services.nginx.after  = [ "selfprivacy-generate-https-cert.service" ];
  systemd.services.nginx.wants  = [ "selfprivacy-generate-https-cert.service" ];

  # ── Firewall ─────────────────────────────────────────────────────────────
  # Port 80 is required for ACME HTTP-01 challenge in production.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
  };

  environment.systemPackages = with pkgs; [
    curl
    htop
    vim
    jq
    openssl
    python3
    valkey
  ];
}
