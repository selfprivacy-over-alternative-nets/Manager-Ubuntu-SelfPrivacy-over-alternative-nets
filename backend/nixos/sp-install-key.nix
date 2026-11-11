# The install key (dev-dashboard req 190): every USB-stick install gets a FRESH key pair on the user's computer; dev-dashboard's
# chain re-masters the installer image with its public half at /sp/authorized_keys. Two halves, both in this file:
#
#   live installer ISO (spInstallKey.iso = true): a one-shot service runs before sshd when /iso/sp/authorized_keys exists — it
#     becomes root's authorized_keys and root gets a long random password, so over SSH the "none" / empty-password login that the
#     plain ISO allows cannot be used any more: only this install's key gets in. The console keeps its autologin.
#
#   installed system (spInstallKey.installed = true): when the config directory holds an `authorized_keys` file (the install copies
#     /iso/sp/authorized_keys next to flake.nix: cp /iso/sp/authorized_keys /mnt/etc/nixos/), root trusts that key and sshd refuses
#     password and empty-password logins. Without the file nothing changes (the VM test flows keep their password-less SSH).
{ config, lib, pkgs, ... }:
let
  cfg = config.spInstallKey;
  keyFile = ../authorized_keys;   # next to flake.nix in the installed config directory
  hasKey = builtins.pathExists keyFile;
in {
  options.spInstallKey = {
    iso = lib.mkEnableOption "trust the install key from the stick (/iso/sp/authorized_keys) in the live installer";
    installed = lib.mkEnableOption "trust ./authorized_keys (copied from the stick at install time) and refuse password logins";
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.iso {
      systemd.services.sp-install-key = {
        description = "SelfPrivacy: trust the install key from the stick, SSH by that key only";
        wantedBy = [ "multi-user.target" ];
        before = [ "sshd.service" ];
        after = [ "local-fs.target" ];
        unitConfig.ConditionPathExists = "/iso/sp/authorized_keys";
        serviceConfig.Type = "oneshot";
        path = [ pkgs.coreutils pkgs.openssl pkgs.shadow ];
        script = ''
          install -d -m 700 /root/.ssh
          install -m 600 /iso/sp/authorized_keys /root/.ssh/authorized_keys
          echo "root:$(openssl rand -base64 48)" | chpasswd
          echo "sp-install-key: SSH accepts only the key from the stick now (root's empty password is gone)"
        '';
      };
    })
    (lib.mkIf (cfg.installed && hasKey) {
      users.users.root.openssh.authorizedKeys.keyFiles = [ keyFile ];
      services.openssh.settings = {
        PermitRootLogin = lib.mkForce "prohibit-password";
        PasswordAuthentication = lib.mkForce false;
        PermitEmptyPasswords = lib.mkForce "no";
        KbdInteractiveAuthentication = lib.mkForce false;
      };
      security.pam.services.sshd.allowNullPassword = lib.mkForce false;
    })
  ];
}
