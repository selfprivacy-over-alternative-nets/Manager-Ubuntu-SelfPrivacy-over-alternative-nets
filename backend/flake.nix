{
  description = "SelfPrivacy Tor VirtualBox Test Image with Real Backend and Services";

  inputs = {
    # Use the same nixpkgs as selfprivacy-api to avoid package incompatibilities
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # SelfPrivacy REST API
    selfprivacy-api = {
      url = "git+https://git.selfprivacy.org/SelfPrivacy/selfprivacy-rest-api.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Integrated services for Tor operation (no SSO required):
  # - monitoring (Prometheus + exporters)
  # - jitsi-meet (video conferencing)
  #
  # Services requiring SSO (will need auth bypass for Tor):
  # - nextcloud, gitea, matrix, bitwarden, pleroma

  outputs = { self, nixpkgs, selfprivacy-api }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # SVG icons for services (base64 encoded for API)
      monitoringIcon = ''<svg width="128" height="128" viewBox="0 0 128 128" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M64.125 0.51C99.229 0.517 128.045 29.133 128 63.951C127.955 99.293 99.258 127.515 63.392 127.49C28.325 127.466 -0.0249987 98.818 1.26289e-06 63.434C0.0230013 28.834 28.898 0.503 64.125 0.51ZM44.72 22.793C45.523 26.753 44.745 30.448 43.553 34.082C42.73 36.597 41.591 39.022 40.911 41.574C39.789 45.777 38.52 50.004 38.052 54.3C37.381 60.481 39.81 65.925 43.966 71.34L24.86 67.318C24.893 67.92 24.86 68.148 24.925 68.342C26.736 73.662 29.923 78.144 33.495 82.372C33.872 82.818 34.732 83.046 35.372 83.046C54.422 83.084 73.473 83.08 92.524 83.055C93.114 83.055 93.905 82.945 94.265 82.565C98.349 78.271 101.47 73.38 103.425 67.223L83.197 71.185C84.533 68.567 86.052 66.269 86.93 63.742C89.924 55.099 88.682 46.744 84.385 38.862C80.936 32.538 77.754 26.242 79.475 18.619C75.833 22.219 74.432 26.798 73.543 31.517C72.671 36.167 72.154 40.881 71.478 45.6C71.38 45.457 71.258 45.35 71.236 45.227C71.1507 44.7338 71.0919 44.2365 71.06 43.737C70.647 36.011 69.14 28.567 65.954 21.457C64.081 17.275 62.013 12.995 63.946 8.001C62.639 8.694 61.456 9.378 60.608 10.357C58.081 13.277 57.035 16.785 56.766 20.626C56.535 23.908 56.22 27.205 55.61 30.432C54.97 33.824 53.96 37.146 51.678 40.263C50.76 33.607 50.658 27.019 44.722 22.793H44.72ZM93.842 88.88H34.088V99.26H93.842V88.88ZM45.938 104.626C45.889 113.268 54.691 119.707 65.571 119.24C74.591 118.851 82.57 111.756 81.886 104.626H45.938Z" fill="black"/></svg>'';

      jitsiIcon = ''<svg width="128" height="128" viewBox="0 0 128 128" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M64 0C28.654 0 0 28.654 0 64C0 99.346 28.654 128 64 128C99.346 128 128 99.346 128 64C128 28.654 99.346 0 64 0ZM97.6 89.6C97.6 93.8 94.2 97.2 90 97.2H38C33.8 97.2 30.4 93.8 30.4 89.6V38.4C30.4 34.2 33.8 30.8 38 30.8H90C94.2 30.8 97.6 34.2 97.6 38.4V89.6Z" fill="black"/><path d="M64 44C56.268 44 50 50.268 50 58C50 65.732 56.268 72 64 72C71.732 72 78 65.732 78 58C78 50.268 71.732 44 64 44Z" fill="black"/><path d="M82 84H46C44.895 84 44 83.105 44 82V76C44 74.895 44.895 74 46 74H82C83.105 74 84 74.895 84 76V82C84 83.105 83.105 84 82 84Z" fill="black"/></svg>'';

      nextcloudIcon = ''<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_51106_4974)"><path d="M12.018 6.53699C9.518 6.53699 7.418 8.24899 6.777 10.552C6.217 9.31999 4.984 8.44699 3.552 8.44699C2.61116 8.45146 1.71014 8.82726 1.04495 9.49264C0.379754 10.158 0.00420727 11.0591 0 12C0.00420727 12.9408 0.379754 13.842 1.04495 14.5073C1.71014 15.1727 2.61116 15.5485 3.552 15.553C4.984 15.553 6.216 14.679 6.776 13.447C7.417 15.751 9.518 17.463 12.018 17.463C14.505 17.463 16.594 15.77 17.249 13.486C17.818 14.696 19.032 15.553 20.447 15.553C21.3881 15.549 22.2895 15.1734 22.955 14.508C23.6205 13.8425 23.9961 12.9411 24 12C23.9958 11.059 23.6201 10.1577 22.9547 9.49229C22.2893 8.82688 21.388 8.4512 20.447 8.44699C19.031 8.44699 17.817 9.30499 17.248 10.514C16.594 8.22999 14.505 6.53599 12.018 6.53699ZM12.018 8.62199C13.896 8.62199 15.396 10.122 15.396 12C15.396 13.878 13.896 15.378 12.018 15.378C11.5739 15.38 11.1338 15.2939 10.7231 15.1249C10.3124 14.9558 9.93931 14.707 9.62532 14.393C9.31132 14.0789 9.06267 13.7057 8.89373 13.295C8.72478 12.8842 8.63888 12.4441 8.641 12C8.641 10.122 10.141 8.62199 12.018 8.62199ZM3.552 10.532C4.374 10.532 5.019 11.177 5.019 12C5.019 12.823 4.375 13.467 3.552 13.468C3.35871 13.47 3.16696 13.4334 2.988 13.3603C2.80905 13.2872 2.64648 13.1792 2.50984 13.0424C2.3732 12.9057 2.26524 12.7431 2.19229 12.5641C2.11934 12.3851 2.08286 12.1933 2.085 12C2.085 11.177 2.729 10.533 3.552 10.533V10.532ZM20.447 10.532C21.27 10.532 21.915 11.177 21.915 12C21.915 12.823 21.27 13.468 20.447 13.468C20.2537 13.47 20.062 13.4334 19.883 13.3603C19.704 13.2872 19.5415 13.1792 19.4048 13.0424C19.2682 12.9057 19.1602 12.7431 19.0873 12.5641C19.0143 12.3851 18.9779 12.1933 18.98 12C18.98 11.177 19.624 10.533 20.447 10.533V10.532Z" fill="black"/></g><defs><clipPath id="clip0_51106_4974"><rect width="24" height="24" fill="white"/></clipPath></defs></svg>'';

      giteaIcon = ''<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2.60007 10.5899L8.38007 4.79995L10.0701 6.49995C9.83007 7.34995 10.2201 8.27995 11.0001 8.72995V14.2699C10.4001 14.6099 10.0001 15.2599 10.0001 15.9999C10.0001 16.5304 10.2108 17.0391 10.5859 17.4142C10.9609 17.7892 11.4696 17.9999 12.0001 17.9999C12.5305 17.9999 13.0392 17.7892 13.4143 17.4142C13.7894 17.0391 14.0001 16.5304 14.0001 15.9999C14.0001 15.2599 13.6001 14.6099 13.0001 14.2699V9.40995L15.0701 11.4999C15.0001 11.6499 15.0001 11.8199 15.0001 11.9999C15.0001 12.5304 15.2108 13.0391 15.5859 13.4142C15.9609 13.7892 16.4696 13.9999 17.0001 13.9999C17.5305 13.9999 18.0392 13.7892 18.4143 13.4142C18.7894 13.0391 19.0001 12.5304 19.0001 11.9999C19.0001 11.4695 18.7894 10.9608 18.4143 10.5857C18.0392 10.2107 17.5305 9.99995 17.0001 9.99995C16.8201 9.99995 16.6501 9.99995 16.5001 10.0699L13.9301 7.49995C14.1901 6.56995 13.7101 5.54995 12.7801 5.15995C12.3501 4.99995 11.9001 4.95995 11.5001 5.06995L9.80007 3.37995L10.5901 2.59995C11.3701 1.80995 12.6301 1.80995 13.4101 2.59995L21.4001 10.5899C22.1901 11.3699 22.1901 12.6299 21.4001 13.4099L13.4101 21.3999C12.6301 22.1899 11.3701 22.1899 10.5901 21.3999L2.60007 13.4099C1.81007 12.6299 1.81007 11.3699 2.60007 10.5899Z" fill="black"/></svg>'';

      matrixIcon = ''<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 520"><path d="M13.7,11.9v496.2h35.7V520H0V0h49.4v11.9H13.7z"/><path d="M166.3,169.2v25.1h0.7c6.7-9.6,14.8-17,24.2-22.2c9.4-5.3,20.3-7.9,32.5-7.9c11.7,0,22.4,2.3,32.1,6.8c9.7,4.5,17,12.6,22.1,24c5.5-8.1,13-15.3,22.4-21.5c9.4-6.2,20.6-9.3,33.5-9.3c9.8,0,18.9,1.2,27.3,3.6c8.4,2.4,15.5,6.2,21.5,11.5c6,5.3,10.6,12.1,14,20.6c3.3,8.5,5,18.7,5,30.7v124.1h-50.9V249.6c0-6.2-0.2-12.1-0.7-17.6c-0.5-5.5-1.8-10.3-3.9-14.3c-2.2-4.1-5.3-7.3-9.5-9.7c-4.2-2.4-9.9-3.6-17-3.6c-7.2,0-13,1.4-17.4,4.1c-4.4,2.8-7.9,6.3-10.4,10.8c-2.5,4.4-4.2,9.4-5,15.1c-0.8,5.6-1.3,11.3-1.3,17v103.3h-50.9v-104c0-5.5-0.1-10.9-0.4-16.3c-0.2-5.4-1.3-10.3-3.1-14.9c-1.8-4.5-4.8-8.2-9-10.9c-4.2-2.7-10.3-4.1-18.5-4.1c-2.4,0-5.6,0.5-9.5,1.6c-3.9,1.1-7.8,3.1-11.5,6.1c-3.7,3-6.9,7.3-9.5,12.9c-2.6,5.6-3.9,13-3.9,22.1v107.6h-50.9V169.2H166.3z"/><path d="M506.3,508.1V11.9h-35.7V0H520v520h-49.4v-11.9H506.3z"/></svg>'';

      mailIcon = ''<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M13.3333 2.66675H2.66665C1.93331 2.66675 1.33998 3.26675 1.33998 4.00008L1.33331 12.0001C1.33331 12.7334 1.93331 13.3334 2.66665 13.3334H13.3333C14.0666 13.3334 14.6666 12.7334 14.6666 12.0001V4.00008C14.6666 3.26675 14.0666 2.66675 13.3333 2.66675ZM13.3333 12.0001H2.66665V5.33341L7.99998 8.66675L13.3333 5.33341V12.0001ZM7.99998 7.33341L2.66665 4.00008H13.3333L7.99998 7.33341Z" fill="black"/></svg>'';

      # Service metadata JSON generator - creates /etc/sp-modules/{service-id} content
      mkServiceMeta = { id, name, description, svgIcon, isMovable ? false, isRequired ? false,
                        canBeBackedUp ? true, backupDescription ? "Service data",
                        systemdServices, folders ? [], license, homepage, sourcePage,
                        supportLevel ? "normal" }: builtins.toJSON {
        meta = {
          spModuleSchemaVersion = 1;
          inherit id name description;
          svgIcon = svgIcon;
          inherit isMovable isRequired canBeBackedUp backupDescription systemdServices folders;
          license = license;
          inherit homepage sourcePage supportLevel;
        };
        configPathsNeeded = [];
        options = {};
      };

      # SelfPrivacy module for Tor-only testing with integrated services
      selfprivacyTorModule = { config, pkgs, lib, ... }:
      let
        redis-sp-api-srv-name = "sp-api";
        selfprivacy-graphql-api = selfprivacy-api.packages.${system}.default;
        workerPython = pkgs.python312.withPackages (ps: [ selfprivacy-graphql-api ps.huey ]);
      in
      {
        # Basic system
        system.stateVersion = "25.11";
        networking.hostName = "selfprivacy-tor";
        time.timeZone = "UTC";

        # Enable Tor with hidden service
        services.tor = {
          enable = true;
          settings = {
            HiddenServiceDir = "/var/lib/tor/hidden_service";
            HiddenServicePort = [
              "80 127.0.0.1:80"
              "443 127.0.0.1:443"
            ];
          };
        };

        # Redis for SelfPrivacy API
        services.redis.package = pkgs.valkey;
        services.redis.servers.${redis-sp-api-srv-name} = {
          enable = true;
          save = [
            [ 30 1 ]
            [ 10 10 ]
          ];
          port = 0; # Unix socket only
          settings = {
            notify-keyspace-events = "KEA";
          };
        };

        # User for API
        users.users.selfprivacy-api = {
          isSystemUser = true;
          group = "selfprivacy-api";
        };
        users.groups.selfprivacy-api = {};
        users.groups.redis-sp-api.members = [ "selfprivacy-api" "root" ];

        # SelfPrivacy API service (simplified for testing)
        systemd.services.selfprivacy-api = {
          description = "SelfPrivacy GraphQL API";
          after = [ "network-online.target" "redis-sp-api.service" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            HOME = "/root";
            PYTHONUNBUFFERED = "1";
            TEST_MODE = "true";  # Enable test mode
          };
          path = with pkgs; [
            coreutils
            gnutar
            xz.bin
            gzip
            gitMinimal
          ];
          serviceConfig = {
            User = "root";
            ExecStart = "${selfprivacy-graphql-api}/bin/app.py";
            Restart = "always";
            RestartSec = "5";
          };
        };

        # Huey worker for background tasks
        systemd.services.selfprivacy-api-worker = {
          description = "SelfPrivacy API Task Worker";
          after = [ "network-online.target" "redis-sp-api.service" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            HOME = "/root";
            PYTHONUNBUFFERED = "1";
            TEST_MODE = "true";
          };
          path = with pkgs; [
            coreutils
            gnutar
            xz.bin
            gzip
            gitMinimal
          ];
          serviceConfig = {
            User = "root";
            ExecStart = "${workerPython}/bin/python -m huey.bin.huey_consumer selfprivacy_api.task_registry.huey";
            Restart = "always";
            RestartSec = "5";
          };
        };

        # Nginx reverse proxy - HTTP for Tor (no TLS needed for .onion)
        services.nginx = {
          enable = true;

          virtualHosts."onion" = {
            listen = [{ addr = "0.0.0.0"; port = 80; }];
            default = true;

            locations."/" = {
              root = pkgs.writeTextDir "index.html" ''
                <!DOCTYPE html>
                <html>
                <head><title>SelfPrivacy Tor Test</title></head>
                <body>
                  <h1>SelfPrivacy over Tor - Real Backend</h1>
                  <p>This server is running the actual SelfPrivacy GraphQL API.</p>
                  <p>Your .onion address is in: <code>/var/lib/tor/hidden_service/hostname</code></p>
                  <h2>API Endpoints:</h2>
                  <ul>
                    <li><a href="/graphql">GraphQL API</a></li>
                    <li><a href="/api/version">API Version</a></li>
                  </ul>
                </body>
                </html>
              '';
              index = "index.html";
            };

            # Proxy GraphQL to SelfPrivacy API
            locations."/graphql" = {
              proxyPass = "http://127.0.0.1:5050";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              '';
            };

            # Proxy REST API endpoints
            locations."/api" = {
              proxyPass = "http://127.0.0.1:5050";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
              '';
            };

            # Proxy Prometheus UI
            locations."/prometheus" = {
              proxyPass = "http://127.0.0.1:9001";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
              '';
            };

            # Proxy Prometheus metrics endpoints
            locations."/prometheus/api" = {
              proxyPass = "http://127.0.0.1:9001/api";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
              '';
            };

            # Jitsi Meet static files - served from the jitsi-meet package
            # Note: Both location and alias must end with / to prevent path traversal
            locations."/jitsi/" = {
              alias = "${pkgs.jitsi-meet}/";
              index = "index.html";
            };

            # Jitsi BOSH for XMPP
            locations."/http-bind" = {
              proxyPass = "http://127.0.0.1:5280/http-bind";
              extraConfig = ''
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header Host $host;
              '';
            };

            # Jitsi WebSocket for XMPP
            locations."/xmpp-websocket" = {
              proxyPass = "http://127.0.0.1:5280/xmpp-websocket";
              extraConfig = ''
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_set_header Host $host;
              '';
            };

            # Nextcloud - proxy to PHP-FPM via fastcgi
            locations."/nextcloud" = {
              proxyPass = "http://127.0.0.1:80";  # Will be handled by nextcloud vhost
              extraConfig = ''
                proxy_set_header Host nextcloud.test.onion;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto http;
              '';
            };

            # Forgejo/Gitea
            # Use /git/ with trailing slash in location, and trailing slash in proxy_pass
            # to properly strip the prefix when proxying
            locations."/git/" = {
              proxyPass = "http://127.0.0.1:3000/";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto http;
              '';
            };
            # Redirect /git to /git/
            locations."= /git" = {
              return = "301 /git/";
            };

            # Matrix Synapse
            locations."/_matrix" = {
              proxyPass = "http://127.0.0.1:8008";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto http;
                client_max_body_size 50M;
              '';
            };

            # Matrix well-known endpoints
            locations."/.well-known/matrix" = {
              extraConfig = ''
                default_type application/json;
                add_header Access-Control-Allow-Origin *;
                return 200 '{"m.homeserver": {"base_url": "http://synapse.test.onion"}, "m.server": "synapse.test.onion:80"}';
              '';
            };
          };
        };

        # Show onion address on console login
        services.getty.helpLine = lib.mkForce ''

          =====================================================
          SelfPrivacy Tor Test VM - Real Backend

          To get your .onion address, run:
            cat /var/lib/tor/hidden_service/hostname

          API Status: systemctl status selfprivacy-api
          API Logs: journalctl -u selfprivacy-api -f

          Default login: root (no password)
          =====================================================
        '';

        # Allow root login without password for testing
        users.users.root = {
          initialHashedPassword = "";
          password = null;
        };
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "yes";
            PermitEmptyPasswords = "yes";
          };
        };
        security.pam.services.sshd.allowNullPassword = true;

        # Firewall - only allow local connections (Tor handles external)
        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 ]; # SSH for local access
        };

        # Useful packages
        environment.systemPackages = with pkgs; [
          curl
          htop
          vim
          tor
          jq
          valkey  # Redis CLI
        ];

        # Display onion address after boot
        systemd.services.show-onion = {
          description = "Display onion address";
          wantedBy = [ "multi-user.target" ];
          after = [ "tor.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            echo "Waiting for Tor to generate .onion address..."
            for i in $(seq 1 120); do
              if [ -f /var/lib/tor/hidden_service/hostname ]; then
                echo ""
                echo "=========================================="
                echo "Your .onion address is:"
                cat /var/lib/tor/hidden_service/hostname
                echo "=========================================="
                echo ""
                break
              fi
              sleep 1
            done
          '';
        };

        # NixOS settings
        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
        };

        # ============================================================
        # NEXTCLOUD SERVICE (Personal Cloud Storage)
        # Simplified version without SSO - uses local admin account
        # ============================================================
        services.nextcloud = {
          enable = true;
          package = pkgs.nextcloud32;
          hostName = "nextcloud.test.onion";
          https = false;  # HTTP for Tor (Tor provides end-to-end encryption)
          autoUpdateApps.enable = true;
          autoUpdateApps.startAt = "05:00:00";
          configureRedis = true;
          settings = {
            overwriteprotocol = "http";  # For Tor operation
            loglevel = 0;
            updatechecker = false;
          };
          config = {
            dbtype = "sqlite";
            adminuser = "admin";
            adminpassFile = "/var/lib/nextcloud/admin-pass";
          };
        };

        # Nextcloud systemd configuration
        systemd.services.phpfpm-nextcloud.serviceConfig.Slice = lib.mkForce "nextcloud.slice";
        systemd.services.nextcloud-setup.serviceConfig.Slice = "nextcloud.slice";
        systemd.services.nextcloud-cron.serviceConfig.Slice = "nextcloud.slice";
        systemd.slices.nextcloud = {
          description = "Nextcloud service slice";
        };

        # Generate admin password if not exists
        systemd.services.nextcloud-secrets = {
          before = [ "nextcloud-setup.service" ];
          requiredBy = [ "nextcloud-setup.service" ];
          serviceConfig.Type = "oneshot";
          path = with pkgs; [ coreutils ];
          script = ''
            mkdir -p /var/lib/nextcloud
            if [ ! -f "/var/lib/nextcloud/admin-pass" ]; then
              cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32 > /var/lib/nextcloud/admin-pass
              chmod 440 /var/lib/nextcloud/admin-pass
            fi
          '';
        };

        # ============================================================
        # GITEA/FORGEJO SERVICE (Git Server)
        # Simplified version without SSO
        # ============================================================
        services.forgejo = {
          enable = true;
          lfs.enable = true;
          settings = {
            DEFAULT.APP_NAME = "SelfPrivacy Git";
            server = {
              # Domain is the .onion hostname (placeholder, actual value set dynamically)
              DOMAIN = "localhost";
              # ROOT_URL must match the nginx location path
              ROOT_URL = "http://localhost/git/";
              HTTP_PORT = 3000;
              HTTP_ADDR = "127.0.0.1";
            };
            service = {
              DISABLE_REGISTRATION = false;  # Allow registration for testing
            };
            session = {
              COOKIE_SECURE = false;  # HTTP for Tor
            };
          };
        };

        # Forgejo systemd configuration
        systemd.services.forgejo.serviceConfig.Slice = "forgejo.slice";
        systemd.slices.forgejo = {
          description = "Forgejo (Gitea) service slice";
        };

        # ============================================================
        # MATRIX SERVICE (Decentralized Chat)
        # Simplified Synapse without MAS (Matrix Authentication Service)
        # Uses local accounts instead of SSO
        # ============================================================
        services.postgresql = {
          enable = true;
          ensureDatabases = [ "matrix-synapse" ];
          ensureUsers = [{
            name = "matrix-synapse";
            ensureDBOwnership = true;
          }];
        };

        services.matrix-synapse = {
          enable = true;
          settings = {
            server_name = "test.onion";
            public_baseurl = "http://synapse.test.onion";
            enable_registration = true;
            enable_registration_without_verification = true;
            allow_guest_access = false;
            database = {
              name = "psycopg2";
              args = {
                user = "matrix-synapse";
                database = "matrix-synapse";
                host = "/run/postgresql";
              };
              # Allow non-C locale for database (not recommended for production)
              allow_unsafe_locale = true;
            };
            listeners = [{
              port = 8008;
              bind_addresses = [ "127.0.0.1" ];
              type = "http";
              tls = false;
              x_forwarded = true;
              resources = [{
                names = [ "client" "federation" ];
                compress = true;
              }];
            }];
          };
        };

        # Matrix systemd configuration
        systemd.services.matrix-synapse.serviceConfig.Slice = "matrix.slice";
        systemd.slices.matrix = {
          description = "Matrix server slice";
        };

        # ============================================================
        # JITSI MEET SERVICE (Video Conferencing)
        # ============================================================
        # Note: For Tor, we use path-based routing since .onion doesn't support subdomains
        # Jitsi is accessible at: http://YOUR_ONION.onion/jitsi/
        nixpkgs.overlays = [
          (final: prev: {
            jitsi-meet = prev.jitsi-meet.overrideAttrs (old: {
              meta = old.meta // {
                # Disable E2EE vulnerability warning (we disable E2EE anyway)
                knownVulnerabilities = [ ];
              };
            });
          })
        ];

        services.jitsi-meet = {
          enable = true;
          hostName = "jitsi.test.onion";  # Virtual hostname for config
          nginx.enable = false;  # We configure nginx manually for Tor path-based routing
          interfaceConfig = {
            SHOW_JITSI_WATERMARK = false;
            SHOW_WATERMARK_FOR_GUESTS = false;
            APP_NAME = "SelfPrivacy Meet";
          };
          config = {
            prejoinConfig.enabled = true;
            e2ee.disabled = true;  # libolm is vulnerable
          };
        };

        # Jitsi systemd slices
        systemd.services.jicofo.serviceConfig.Slice = "jitsi_meet.slice";
        systemd.services.jitsi-videobridge2.serviceConfig.Slice = "jitsi_meet.slice";
        systemd.services.prosody.serviceConfig.Slice = "jitsi_meet.slice";
        systemd.slices.jitsi_meet = {
          description = "Jitsi Meet service slice";
        };

        # ============================================================
        # MONITORING SERVICE (Prometheus + Node Exporter + cAdvisor)
        # ============================================================
        services.cadvisor = {
          enable = true;
          port = 9003;
          listenAddress = "127.0.0.1";
          extraOptions = [ "--enable_metrics=cpu,memory,diskIO" ];
        };

        services.prometheus = {
          enable = true;
          port = 9001;
          listenAddress = "127.0.0.1";
          # External URL is required for proper path-based routing
          webExternalUrl = "http://localhost/prometheus";
          exporters = {
            node = {
              enable = true;
              enabledCollectors = [ "systemd" ];
              port = 9002;
              listenAddress = "127.0.0.1";
            };
          };
          scrapeConfigs = [
            {
              job_name = "node-exporter";
              static_configs = [{ targets = [ "127.0.0.1:9002" ]; }];
            }
            {
              job_name = "cadvisor";
              static_configs = [{ targets = [ "127.0.0.1:9003" ]; }];
            }
            {
              job_name = "selfprivacy-api";
              static_configs = [{ targets = [ "127.0.0.1:5050" ]; }];
            }
          ];
        };

        # Monitoring systemd slices
        systemd.services.prometheus.serviceConfig.Slice = "monitoring.slice";
        systemd.services.prometheus-node-exporter.serviceConfig.Slice = "monitoring.slice";
        systemd.services.cadvisor.serviceConfig.Slice = "monitoring.slice";
        systemd.slices.monitoring = {
          description = "Monitoring service slice";
        };

        # Required directories and files for SelfPrivacy API
        systemd.tmpfiles.rules = [
          "d /var/lib/selfprivacy 0755 root root - -"
          "d /etc/nixos 0755 root root - -"
          "d /etc/selfprivacy 0755 root root - -"
          "d /etc/sp-modules 0755 root root - -"
          "d /var/lib/prometheus2 0755 prometheus prometheus - -"
        ];

        # Create minimal config files for SelfPrivacy API
        environment.etc."selfprivacy/secrets.json" = {
          text = builtins.toJSON {
            api = {
              token = "test-token-for-tor-development";
            };
          };
          mode = "0600";
        };

        # Create writable sp-modules/flake.nix on first boot
        # The SelfPrivacy API's FlakeServiceManager reads and writes this file
        systemd.services.selfprivacy-init-sp-modules = {
          description = "Initialize writable SelfPrivacy sp-modules";
          wantedBy = [ "multi-user.target" ];
          before = [ "selfprivacy-api.service" ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          script = ''
            mkdir -p /etc/nixos/sp-modules
            if [ ! -f /etc/nixos/sp-modules/flake.nix ]; then
              cat > /etc/nixos/sp-modules/flake.nix << 'EOFLAKE'
            {
              description = "SelfPrivacy NixOS PoC modules/extensions/bundles/packages/etc";
              outputs = _: { };
            }
            EOFLAKE
              chmod 644 /etc/nixos/sp-modules/flake.nix
            fi
          '';
        };

        # Create a writable userdata.json on first boot
        # NixOS etc files are read-only symlinks to the Nix store,
        # but the SelfPrivacy API needs to write to this file
        systemd.services.selfprivacy-init-userdata = {
          description = "Initialize writable SelfPrivacy userdata";
          wantedBy = [ "multi-user.target" ];
          before = [ "selfprivacy-api.service" ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          script = ''
            mkdir -p /etc/nixos
            if [ ! -f /etc/nixos/userdata.json ]; then
              cat > /etc/nixos/userdata.json << 'EOJSON'
            ${builtins.toJSON {
              username = "admin";
              hashedPassword = "";
              sshKeys = [];
              dns = { provider = "NONE"; };
              server = { provider = "NONE"; };
              domain = "test.onion";
              autoUpgrade = { enable = false; };
              timezone = "UTC";
              modules = {
                nextcloud = { enable = true; };
                gitea = { enable = true; };
                jitsi-meet = { enable = true; };
                monitoring = { enable = true; };
                matrix = { enable = true; };
              };
            }}
            EOJSON
              chmod 600 /etc/nixos/userdata.json
            fi
          '';
        };

        # ============================================================
        # SERVICE METADATA FOR SELFPRIVACY API DISCOVERY
        # Each file in /etc/sp-modules/{id} describes a service
        # ============================================================

        # Monitoring service metadata
        environment.etc."sp-modules/monitoring" = {
          text = mkServiceMeta {
            id = "monitoring";
            name = "Prometheus";
            description = "Prometheus is used for resource monitoring and alerts. Includes node-exporter and cAdvisor for comprehensive system metrics.";
            svgIcon = monitoringIcon;
            isMovable = false;
            isRequired = true;
            canBeBackedUp = false;
            backupDescription = "Backups are not available for Prometheus metrics data.";
            systemdServices = [ "prometheus.service" ];
            folders = [ "/var/lib/prometheus2" ];
            license = [{ deprecated = false; free = true; redistributable = true; fullName = "Apache License 2.0"; shortName = "Apache-2.0"; url = "https://www.apache.org/licenses/LICENSE-2.0"; }];
            homepage = "https://prometheus.io/";
            sourcePage = "https://github.com/prometheus/prometheus";
            supportLevel = "normal";
          };
          mode = "0644";
        };

        # Jitsi Meet service metadata
        environment.etc."sp-modules/jitsi-meet" = {
          text = mkServiceMeta {
            id = "jitsi-meet";
            name = "Jitsi Meet";
            description = "Jitsi Meet is a free and open-source video conferencing solution. Access via /jitsi/ path on your .onion address.";
            svgIcon = jitsiIcon;
            isMovable = false;
            isRequired = false;
            canBeBackedUp = true;
            backupDescription = "Secrets used to encrypt communication between Jitsi components.";
            systemdServices = [ "prosody.service" "jitsi-videobridge2.service" "jicofo.service" ];
            folders = [ "/var/lib/jitsi-meet" ];
            license = [{ deprecated = false; free = true; redistributable = true; fullName = "Apache License 2.0"; shortName = "Apache-2.0"; url = "https://www.apache.org/licenses/LICENSE-2.0"; }];
            homepage = "https://jitsi.org/meet";
            sourcePage = "https://github.com/jitsi/jitsi-meet";
            supportLevel = "normal";
          };
          mode = "0644";
        };

        # Nextcloud service metadata
        environment.etc."sp-modules/nextcloud" = {
          text = mkServiceMeta {
            id = "nextcloud";
            name = "Nextcloud";
            description = "Nextcloud is a personal cloud storage solution for files, calendar, and contacts. Access via /nextcloud/ path. Login: admin / see /var/lib/nextcloud/admin-pass";
            svgIcon = nextcloudIcon;
            isMovable = false;
            isRequired = false;
            canBeBackedUp = true;
            backupDescription = "All your files, calendar entries, contacts, and database.";
            systemdServices = [ "phpfpm-nextcloud.service" ];
            folders = [ "/var/lib/nextcloud" ];
            license = [{ deprecated = false; free = true; redistributable = true; fullName = "GNU Affero General Public License v3.0"; shortName = "AGPL-3.0"; url = "https://www.gnu.org/licenses/agpl-3.0.html"; }];
            homepage = "https://nextcloud.com/";
            sourcePage = "https://github.com/nextcloud/server";
            supportLevel = "normal";
          };
          mode = "0644";
        };

        # Forgejo/Gitea service metadata
        environment.etc."sp-modules/gitea" = {
          text = mkServiceMeta {
            id = "gitea";
            name = "Forgejo";
            description = "Forgejo is a self-hosted Git service (Gitea fork). Access via /git/ path on your .onion address.";
            svgIcon = giteaIcon;
            isMovable = false;
            isRequired = false;
            canBeBackedUp = true;
            backupDescription = "All Git repositories, issues, pull requests, and user data.";
            systemdServices = [ "forgejo.service" ];
            folders = [ "/var/lib/forgejo" ];
            license = [{ deprecated = false; free = true; redistributable = true; fullName = "MIT License"; shortName = "MIT"; url = "https://opensource.org/licenses/MIT"; }];
            homepage = "https://forgejo.org/";
            sourcePage = "https://codeberg.org/forgejo/forgejo";
            supportLevel = "normal";
          };
          mode = "0644";
        };

        # Matrix service metadata
        environment.etc."sp-modules/matrix" = {
          text = mkServiceMeta {
            id = "matrix";
            name = "Matrix Synapse";
            description = "Matrix Synapse is a decentralized communication server. Access client APIs via /_matrix/ path.";
            svgIcon = matrixIcon;
            isMovable = false;
            isRequired = false;
            canBeBackedUp = true;
            backupDescription = "All Matrix rooms, messages, and user data.";
            systemdServices = [ "matrix-synapse.service" ];
            folders = [ "/var/lib/matrix-synapse" ];
            license = [{ deprecated = false; free = true; redistributable = true; fullName = "Apache License 2.0"; shortName = "Apache-2.0"; url = "https://www.apache.org/licenses/LICENSE-2.0"; }];
            homepage = "https://matrix.org/";
            sourcePage = "https://github.com/element-hq/synapse";
            supportLevel = "normal";
          };
          mode = "0644";
        };

        # Note: Mail Server is not enabled for Tor because:
        # 1. .onion addresses cannot have MX DNS records
        # 2. Email federation requires clearnet DNS
        # 3. Most email providers block Tor exit nodes
        # For Tor-based messaging, use Matrix instead.
      };
    in
    {
      # NixOS configuration for installation
      nixosConfigurations.selfprivacy-tor-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          selfprivacyTorModule
          ({ modulesPath, ... }: {
            imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
            boot.loader.grub.enable = true;
            boot.loader.grub.device = "/dev/sda";
            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };
            virtualisation.virtualbox.guest.enable = true;
          })
        ];
      };

      # Build ISO installer
      packages.${system}.default = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ({ pkgs, lib, modulesPath, ... }: {
            # Include the selfprivacy flake config in the ISO
            isoImage.contents = [
              {
                source = self;
                target = "/selfprivacy-config";
              }
            ];

            # Enable SSH with empty password for automated install
            services.openssh = {
              enable = true;
              settings = {
                PermitRootLogin = "yes";
                PermitEmptyPasswords = "yes";
              };
            };

            # Allow empty passwords through PAM
            security.pam.services.sshd.allowNullPassword = true;

            # Set root to have no password
            users.users.root = {
              initialHashedPassword = "";
              password = null;
            };

            services.getty.helpLine = lib.mkForce ''

              =====================================================
              SelfPrivacy Tor Installer ISO - Real Backend
              SSH enabled - root with no password
              =====================================================
            '';

            environment.systemPackages = with pkgs; [ git vim parted ];
          })
        ];
      }).config.system.build.isoImage;

    };
}
