#!/usr/bin/env python3
"""Headless core for MuseSetup.app. Reads MUSE_PROXY_USER / MUSE_PROXY_PASS / META_API_KEY."""

import json
import os
import pathlib
import shutil
import subprocess
import sys
import urllib.parse

HOST = "184.197.234.208:8443"


def main() -> None:
    user = os.environ["MUSE_PROXY_USER"]
    pwd = os.environ["MUSE_PROXY_PASS"]
    key = os.environ["META_API_KEY"]

    proxy = (
        f"http://{urllib.parse.quote(user, safe='')}:"
        f"{urllib.parse.quote(pwd, safe='')}@{HOST}"
    )

    exe = shutil.which("muse") or str(pathlib.Path.home() / ".local/bin/muse")
    if not pathlib.Path(exe).exists():
        print("Installing Muse CLI…", flush=True)
        subprocess.run(["sh", "-c", "curl -fsSL https://dev.meta.ai/install.sh | sh"], check=True)
        exe = str(pathlib.Path.home() / ".local/bin/muse")

    config = pathlib.Path.home() / ".config" / "muse"
    settings_path = config / "settings.json"
    config.mkdir(parents=True, exist_ok=True)
    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
    settings.setdefault("schema_version", 1)
    settings.setdefault("endpoint_transport", {})["proxy"] = proxy
    settings_path.write_text(json.dumps(settings, indent=2) + "\n")
    settings_path.chmod(0o600)

    route_dir = pathlib.Path.home() / ".config" / "muse-vpn"
    route_dir.mkdir(parents=True, exist_ok=True)
    route_file = route_dir / "proxy-url"
    route_file.write_text(proxy + "\n")
    route_file.chmod(0o600)

    stored = subprocess.run(
        [exe, "auth", "set", "--provider", "meta", "--api-key-stdin"],
        input=key + "\n", text=True, capture_output=True,
    )
    if stored.returncode != 0:
        sys.exit("could not store the API key: " + stored.stderr.strip())

    print("Verifying…", flush=True)
    check = subprocess.run(
        [exe, "exec", "reply with exactly: setup-ok"],
        text=True, capture_output=True, timeout=240,
    )
    if "setup-ok" not in check.stdout:
        sys.exit((check.stdout + check.stderr).strip()[-700:])

    print("OK")


if __name__ == "__main__":
    main()
