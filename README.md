# muse-setup

One-click installers for Muse Code, pointed at the team egress proxy (the
model API is not reachable from our region directly; the proxy changes only
the egress country, your code and commands stay on your machine).

Two deliverables:

```
desktop/macos/MuseSetup.app     double-click app (native dialogs)
desktop/windows/MuseSetup.cmd   double-click installer (Windows Forms dialogs)
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

## Windows

1. Unzip and run `MuseSetup.cmd`.
2. If SmartScreen blocks it: **More info -> Run anyway**.
3. Enter proxy username, proxy password, and your Meta API key.
4. Success dialog -> open a terminal in a project and run `muse`.

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
