# muse-setup

One-click installers for Muse Code, pointed at the team egress proxy (the
model API is not reachable from our region directly; the proxy changes only
the egress country, your code and commands stay on your machine).

Two deliverables:

```
desktop/macos/Pantheon Egress.app  single app: setup, toggle, menu bar, HTML UI
desktop/windows/PantheonSetup.exe setup wizard (no console)
desktop/windows/PantheonTray.exe  tray toggle (no console)
desktop/windows/PantheonSetup.cmd script fallback
```

## What you need before running

1. **Proxy credentials** from your admin (username + password).
2. **Your own Meta API key**: sign in at <https://dev.meta.ai> -> API Keys ->
   Create. Keys look like `LLM_...`. Do not share a key with anyone.

## macOS

1. Copy `MuseSetup.app` to your Desktop (or anywhere).
2. First launch only: **right-click -> Open**. macOS quarantines downloaded
   apps; a plain double-click may refuse to run. Alternatively:

   ```sh
   xattr -dr com.apple.quarantine /path/to/MuseSetup.app
   ```

3. Enter proxy username, proxy password, and your Meta API key (both secrets
   are masked).
4. Success dialog -> open Terminal in a project and run `muse`.

## macOS: egress toggle

`Pantheon Egress.app` puts an icon in the menu bar and opens a small window rendered with HTML/CSS (`desktop/macos/src/ui.html`, displayed in a WKWebView): 🌐 = US egress on, ○ = off
(direct). Click it to switch; no dialogs, no prompts. It flips the `proxy`
key in `~/.config/muse/settings.json` using the URL saved at
`~/.config/muse-vpn/proxy-url`.

Headless controls, same binary:

```sh
desktop/macos/Pantheon Egress.app/Contents/MacOS/MuseProxy --status   # on|off
desktop/macos/Pantheon Egress.app/Contents/MacOS/MuseProxy --toggle
```

Rebuild from source (needs Xcode command-line tools):

```sh
swiftc -O desktop/macos/src/MuseProxy.swift -o MuseProxy -framework Cocoa
```

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
