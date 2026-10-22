# muse-setup

One-click installers for Muse Code, pointed at the team egress proxy (the
model API is not reachable from our region directly; the proxy changes only
the egress country, your code and commands stay on your machine).

Two deliverables:

```
desktop/cli/pantheon.py     CLI: status / on / off / heal / config / setup / doctor
desktop/cli/setup.py        installer core used by `pantheon setup`
desktop/windows/pantheon.ps1     Windows CLI (same subcommands)
desktop/windows/PantheonSetup.exe  Windows setup wizard (no console)
desktop/windows/PantheonTray.exe   Windows tray toggle
```

## What you need before running

1. **Proxy credentials** from your admin (username + password).
2. **Your own Meta API key**: sign in at <https://dev.meta.ai> -> API Keys ->
   Create. Keys look like `LLM_...`. Do not share a key with anyone.

## macOS (CLI)

```sh
ln -sf "$PWD/desktop/cli/pantheon.py" ~/.local/bin/pantheon
cp desktop/cli/setup.py ~/.config/muse-vpn/setup.py
pantheon setup        # proxy login + your own API key
pantheon status       # route, repair config, credential state
pantheon doctor       # test the route (add --heal to self-repair)
```

| command | does |
|---|---|
| `pantheon on` / `off` | enable/disable the US route |
| `pantheon status` | route, repair config, credential, muse install |
| `pantheon heal` | re-point the SSH firewall rule at this IP |
| `pantheon config <https-url>` | load `{"route": "..."}` from a URL |
| `pantheon setup` | install/configure muse |
| `pantheon doctor [--heal]` | test the route, optionally heal and retest |

## Changing the route without a new build

The route lives outside the app, in `~/.config/muse-vpn/proxy-url`. In the app:
**Set Up / Change Key… -> Config URL -> Load**. It downloads JSON of the form

```json
{ "route": "http://user:pass@host:port" }
```

validates it, saves it, and applies it immediately. Host that file anywhere
(GitHub raw, S3, a gist in a private repo) and every install can pick up a new
route without rebuilding or redistributing the app.

The config URL must be `https`.

## Auto-heal (SSH IP changes)

ISP addresses change often, which breaks the security-group rule for SSH. The
app has **Repair connection** (window link + menu). It POSTs to a Lambda
Function URL that rewrites the SSH rule to the caller's current IP.

Config lives in `~/.config/muse-vpn/heal.json` (mode 600):

```json
{ "url": "https://<id>.lambda-url.us-east-1.on.aws/", "token": "<shared secret>" }
```

Setup also retries once automatically after a heal when verification fails with
a transport/timeout error. The endpoint only edits the SSH ingress rule; it
grants no shell without the private key. Deployment source is in
`ops/lambda/pantheon_heal.py`.

## Windows (CLI)

```bat
pantheon.cmd status
pantheon.cmd setup
pantheon.cmd on | off | heal | doctor --heal
pantheon.cmd config https://example.com/route.json
```

Same subcommands as macOS. `pantheon.ps1` is plain PowerShell 5.1; no extra runtime.

## Windows

1. Unzip and run **`PantheonSetup.exe`** (no console window). If your AV blocks
   an unsigned exe, use `PantheonSetup.cmd`, which runs the same wizard as a
   script.
2. Optional: run **`PantheonTray.exe`** for a tray icon that toggles the route
   on/off (same idea as the macOS menu-bar app).
3. Original script steps:
4. If SmartScreen blocks it: **More info -> Run anyway**.
5. Enter proxy username, proxy password, and your Meta API key.
6. Success dialog -> open a terminal in a project and run `muse`.

The `.exe` files are thin launchers: they run the same PowerShell wizard
embedded as an encoded command, with no console window.
Cross-build them yourself with `desktop/windows/src/build.sh` (Go required).

## What the installer changes

- Installs the Muse CLI if `muse` is not already on your PATH (official
  installer from `dev.meta.ai`).
- Writes the proxy setting to `~/.config/muse/settings.json`
  (`%USERPROFILE%\.config\muse\settings.json` on Windows), mode 0600.
- Stores your API key with `muse auth set` (macOS Keychain / system store).
- Runs one real turn to verify the setup.

It does not install anything else, does not touch your shell profile, and
contains no credentials.

## Troubleshooting

| symptom | cause | fix |
|---|---|---|
| `transport error` / `timed out` | proxy unreachable or down | tell your admin |
| `invalid_api_key` | key typed wrong, or revoked | create a new key, re-run setup |
| `no visible models` | proxy not applied, or no plan on the account | re-run setup; check billing at dev.meta.ai |
| app will not open (macOS) | quarantine | right-click -> Open, or `xattr -dr com.apple.quarantine` |
| PowerShell blocked | execution policy | the `.cmd` already uses `-ExecutionPolicy Bypass` |

## Uninstall

```sh
muse logout                       # remove the stored credential
rm -rf ~/.config/muse ~/.local/share/muse
```

Windows: `muse logout`, then delete `%USERPROFILE%\.config\muse`.
