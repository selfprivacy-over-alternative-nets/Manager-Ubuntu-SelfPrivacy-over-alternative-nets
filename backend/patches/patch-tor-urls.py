"""
Patch SelfPrivacy API Python files for Tor subpath URL routing.

This script:
1. Patches Service.get_url() to return subpath URLs for .onion domains
2. Patches TemplatedService.get_url() similarly
3. Patches Prometheus.get_url() (hardcoded static method)
4. Patches SelfPrivacyAPI.get_url() (hardcoded static method)
5. Patches user repository to use JsonUserRepository instead of Kanidm
6. Bind-mounts all patched files over the originals in the nix store

Usage: python3 patch-tor-urls.py <site-packages-path>
"""

import os
import subprocess
import sys

site_pkg = sys.argv[1]

TOR_PATHS_CODE = '''
# Tor subpath URL mapping (service_id -> nginx path)
_TOR_SERVICE_PATHS = {
    "nextcloud": "/nextcloud/",
    "gitea": "/git/",
    "jitsi-meet": "/jitsi/",
    "matrix": "/_matrix/",
    "monitoring": "/prometheus/",
    "selfprivacy-api": "/api/",
}
'''


def patch_and_mount(src_rel, dest_path, patch_fn):
    """Copy file, apply patch function, bind-mount over original."""
    src = os.path.join(site_pkg, src_rel)
    with open(src, "r") as f:
        content = f.read()
    content = patch_fn(content)
    with open(dest_path, "w") as f:
        f.write(content)
    subprocess.run(["mount", "--bind", dest_path, src], check=True)
    print(f"Patched and mounted: {src_rel}")


def patch_service_py(content):
    """Patch base Service.get_url() for Tor subpath routing."""
    marker = "from selfprivacy_api.services.owned_path import OwnedPath, Bind"
    content = content.replace(marker, marker + "\n" + TOR_PATHS_CODE)

    old = (
        '    @classmethod\n'
        '    def get_url(cls) -> Optional[str]:\n'
        '        """\n'
        '        The url of the service if it is accessible from the internet browser.\n'
        '        """\n'
        '        domain = get_domain()\n'
        '        subdomain = cls.get_subdomain()\n'
        '        return f"https://{subdomain}.{domain}"'
    )
    new = (
        '    @classmethod\n'
        '    def get_url(cls) -> Optional[str]:\n'
        '        """\n'
        '        The url of the service if it is accessible from the internet browser.\n'
        '        For .onion domains, returns subpath-based URLs matching nginx config.\n'
        '        """\n'
        '        domain = get_domain()\n'
        '        if domain and domain.endswith(".onion"):\n'
        '            path = _TOR_SERVICE_PATHS.get(cls.get_id())\n'
        '            if path:\n'
        '                return f"http://{domain}{path}"\n'
        '        subdomain = cls.get_subdomain()\n'
        '        return f"https://{subdomain}.{domain}"'
    )
    content = content.replace(old, new)
    return content


def patch_templated_service_py(content):
    """Patch TemplatedService.get_url() for Tor subpath routing."""
    marker = "from selfprivacy_api.utils.systemd import ("
    content = content.replace(marker, TOR_PATHS_CODE + "\n" + marker)

    old = (
        '    def get_url(self) -> Optional[str]:\n'
        '        if not self.meta.showUrl:\n'
        '            return None\n'
        '        subdomain = self.get_subdomain()\n'
        '        if not subdomain:\n'
        '            return None\n'
        '        return f"https://{subdomain}.{get_domain()}"'
    )
    new = (
        '    def get_url(self) -> Optional[str]:\n'
        '        if not self.meta.showUrl:\n'
        '            return None\n'
        '        domain = get_domain()\n'
        '        if domain and domain.endswith(".onion"):\n'
        '            path = _TOR_SERVICE_PATHS.get(self.get_id())\n'
        '            if path:\n'
        '                return f"http://{domain}{path}"\n'
        '        subdomain = self.get_subdomain()\n'
        '        if not subdomain:\n'
        '            return None\n'
        '        return f"https://{subdomain}.{domain}"'
    )
    content = content.replace(old, new)
    return content


def patch_prometheus_init(content):
    """Patch Prometheus.get_url() to return URL for .onion domains."""
    content = content.replace(
        "from selfprivacy_api.services.service import Service, ServiceStatus",
        "from selfprivacy_api.services.service import Service, ServiceStatus\n"
        "from selfprivacy_api.utils import get_domain"
    )
    old = (
        '    @staticmethod\n'
        '    def get_url() -> Optional[str]:\n'
        '        """Return service url."""\n'
        '        return None'
    )
    new = (
        '    @staticmethod\n'
        '    def get_url() -> Optional[str]:\n'
        '        """Return service url."""\n'
        '        domain = get_domain()\n'
        '        if domain and domain.endswith(".onion"):\n'
        '            return f"http://{domain}/prometheus/"\n'
        '        return None'
    )
    content = content.replace(old, new)
    return content


def patch_services_init(content):
    """Patch SelfPrivacyAPI.get_url() for Tor subpath routing."""
    old = (
        '    @staticmethod\n'
        '    def get_url() -> typing.Optional[str]:\n'
        '        """Return service url."""\n'
        '        domain = get_domain()\n'
        '        return f"https://api.{domain}"'
    )
    new = (
        '    @staticmethod\n'
        '    def get_url() -> typing.Optional[str]:\n'
        '        """Return service url."""\n'
        '        domain = get_domain()\n'
        '        if domain and domain.endswith(".onion"):\n'
        '            return f"http://{domain}/api/"\n'
        '        return f"https://api.{domain}"'
    )
    content = content.replace(old, new)
    return content


def patch_users_init(content):
    """Use JsonUserRepository instead of KanidmUserRepository."""
    return (
        "from selfprivacy_api.repositories.users.json_user_repository import JsonUserRepository\n"
        "\n"
        "ACTIVE_USERS_PROVIDER = JsonUserRepository\n"
    )


# Apply all patches
patch_and_mount(
    "selfprivacy_api/services/service.py",
    "/tmp/sp-patched-service.py",
    patch_service_py,
)
patch_and_mount(
    "selfprivacy_api/services/templated_service.py",
    "/tmp/sp-patched-templated-service.py",
    patch_templated_service_py,
)
patch_and_mount(
    "selfprivacy_api/services/prometheus/__init__.py",
    "/tmp/sp-patched-prometheus-init.py",
    patch_prometheus_init,
)
patch_and_mount(
    "selfprivacy_api/services/__init__.py",
    "/tmp/sp-patched-services-init.py",
    patch_services_init,
)
patch_and_mount(
    "selfprivacy_api/repositories/users/__init__.py",
    "/tmp/sp-patched-users-init.py",
    patch_users_init,
)

print("All Tor patches applied via bind-mount")
