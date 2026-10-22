#!/usr/bin/env python3
"""pantheon — Muse route CLI.

    pantheon status            show route, repair config, credential state
    pantheon on | off          enable/disable the US route
    pantheon heal              re-point the SSH firewall rule at this IP
    pantheon config <url>      load {"route": "..."} JSON from an https URL
    pantheon setup             install/configure muse (prompts for secrets)
    pantheon doctor [--heal]   test the route, optionally heal and retest
"""

from __future__ import annotations

import getpass
import json
import os
import pathlib
import subprocess
import sys
import time

HOME = pathlib.Path.home()
SETTINGS = HOME / ".config/muse/settings.json"
ROUTE_FILE = HOME / ".config/muse-vpn/proxy-url"
HEAL_FILE = HOME / ".config/muse-vpn/heal.json"
SETUP = HOME / ".config/muse-vpn/setup.py"
MUSE = pathlib.Path("/usr/local/bin/muse")
if not MUSE.exists():
    MUSE = HOME / ".local/bin/muse"


# ---------------------------------------------------------------- storage

def read_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def write_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    path.chmod(0o600)


def route() -> str | None:
    try:
        value = ROUTE_FILE.read_text().strip()
        return value or None
    except Exception:
        return None


def save_route(url: str) -> None:
    ROUTE_FILE.parent.mkdir(parents=True, exist_ok=True)
    ROUTE_FILE.write_text(url + "\n")
    ROUTE_FILE.chmod(0o600)


def active_proxy() -> str | None:
    return read_json(SETTINGS).get("endpoint_transport", {}).get("proxy")


def set_proxy(url: str | None) -> None:
    data = read_json(SETTINGS)
    data.setdefault("schema_version", 1)
    transport = data.setdefault("endpoint_transport", {})
    if url:
        transport["proxy"] = url
    else:
        transport.pop("proxy", None)
    write_json(SETTINGS, data)


def hide(url: str | None) -> str:
    if not url:
        return "—"
    rest = url.split("@")[-1]
    return rest.split("://")[-1]


def heal_config() -> tuple[str, str] | None:
    data = read_json(HEAL_FILE)
    if data.get("url") and data.get("token"):
        return data["url"], data["token"]
    return None


def curl(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["curl", "-sS", "-m", "25", *args], text=True, capture_output=True)


# ---------------------------------------------------------------- commands

def cmd_status() -> int:
    on = active_proxy() is not None
    print(f"route      : {'ON  -> ' + hide(active_proxy()) if on else 'OFF (direct)'}")
    print(f"saved      : {hide(route())}")
    print(f"repair     : {'configured' if heal_config() else 'not configured'}")
    providers = read_json(HOME / ".config/muse/auth.json").get("providers", {})
    print(f"credential : {'present (' + ', '.join(providers) + ')' if providers else 'none — run pantheon setup'}")
    print(f"muse       : {'installed' if MUSE.exists() else 'missing'}")
    return 0


def cmd_on() -> int:
    url = route()
    if not url:
        print("no route saved; run: pantheon config <url>", file=sys.stderr)
        return 1
    set_proxy(url)
    print(f"route ON -> {hide(url)}")
    return 0


def cmd_off() -> int:
    set_proxy(None)
    print("route OFF (direct)")
    return 0


def cmd_heal() -> int:
    cfg = heal_config()
    if not cfg:
        print("no repair config at ~/.config/muse-vpn/heal.json", file=sys.stderr)
        return 1
    url, token = cfg
    proc = curl(["-X", "POST", url, "-H", "content-type: application/json",
                 "-d", json.dumps({"token": token})])
    if proc.returncode != 0:
        print(f"repair failed: {proc.stderr.strip()}", file=sys.stderr)
        return 1
    try:
        payload = json.loads(proc.stdout or "{}")
    except Exception:
        payload = {}
    cidr = payload.get("cidr")
    if not cidr:
        print(f"repair failed: {proc.stdout.strip() or proc.stderr.strip()}", file=sys.stderr)
        return 1
    print(f"repaired for {cidr}")
    return 0


def cmd_config(url: str) -> int:
    if not url.startswith("https://"):
        print("config URL must be https", file=sys.stderr)
        return 1
    proc = curl([url])
    if proc.returncode != 0:
        print(f"download failed: {proc.stderr.strip()}", file=sys.stderr)
        return 1
    try:
        data = json.loads(proc.stdout)
    except Exception:
        print("config is not valid JSON", file=sys.stderr)
        return 1
    new_route = (data.get("route") or "").strip()
    if not new_route:
        print('config must contain {"route": "http://user:pass@host:port"}', file=sys.stderr)
        return 1
    save_route(new_route)
    if active_proxy() is not None:
        set_proxy(new_route)
    print(f"route updated -> {hide(new_route)}")
    return 0


def cmd_setup() -> int:
    if not SETUP.exists():
        print(f"missing {SETUP}", file=sys.stderr)
        return 1
    user = input("Proxy username: ").strip()
    password = getpass.getpass("Proxy password: ")
    key = getpass.getpass("Meta API key: ").strip()
    if not (user and password and key):
        print("all three values are required", file=sys.stderr)
        return 1
    env = os.environ.copy()
    env.update(MUSE_PROXY_USER=user, MUSE_PROXY_PASS=password, META_API_KEY=key)
    if route():
        env["MUSE_ROUTE_URL"] = route()
    return subprocess.call([sys.executable, str(SETUP)], env=env)


def test_route() -> tuple[bool, str]:
    url = active_proxy() or route()
    if not url:
        return False, "no route configured"
    proc = curl(["-x", url, "-o", "/dev/null", "-w", "%{http_code} %{time_total}",
                 "https://api.meta.ai/v1/models"])
    if proc.returncode != 0:
        return False, f"route FAILED ({proc.stderr.strip()})"
    parts = proc.stdout.split()
    code = parts[0] if parts else "000"
    elapsed = parts[1] if len(parts) > 1 else "?"
    ok = code in ("200", "401", "403")
    note = " (credential missing or rejected)" if code in ("401", "403") else ""
    return ok, f"route {'OK' if ok else 'FAILED'} (HTTP {code}, {elapsed}s){note}"


def cmd_doctor(heal: bool) -> int:
    ok, message = test_route()
    print(message)
    if ok or not heal:
        return 0 if ok else 1
    print("trying repair…")
    if cmd_heal() != 0:
        return 1
    ok, message = test_route()
    print(message)
    return 0 if ok else 1


def main() -> int:
    args = sys.argv[1:]
    command = args[0] if args else "status"
    if command == "status":
        return cmd_status()
    if command == "on":
        return cmd_on()
    if command == "off":
        return cmd_off()
    if command == "heal":
        return cmd_heal()
    if command == "config":
        if len(args) < 2:
            print("usage: pantheon config <https-url>", file=sys.stderr)
            return 1
        return cmd_config(args[1])
    if command == "setup":
        return cmd_setup()
    if command == "doctor":
        return cmd_doctor("--heal" in args[1:])
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
