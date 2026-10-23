# pantheon

One CLI for Muse Code behind the company egress route. The model API is not
reachable from our region directly; the route changes only the egress country.
Your code, files and commands stay on your machine.

## Install

```sh
ln -sf "$PWD/cli/pantheon" ~/.local/bin/pantheon
```

## Interactive

The header shows the Pantheon owl on terminals at least 118 columns wide, and
falls back to the wordmark on narrower ones (the art is in `ascii-art-3.txt`).



Run `pantheon` with no arguments (on a terminal) for the menu:

```
  Route       ● ON  Pantheon Routes
  Repair      ● configured
  Credential  ● none — run Setup
  Muse        ● installed

  ❯ Set up / change key
    Toggle route
    Test route (doctor)
    Repair connection (heal)
    Load config URL
    Refresh
    Quit
```

Arrow keys to move, Enter to pick, `q` to quit. Plain subcommands below still
work for scripts and CI.

## Commands

| command | does |
|---|---|
| `pantheon setup` | installs muse if needed, stores your own API key, configures the route, verifies with a real turn |
| `pantheon status` | route, repair config, credential and muse state |
| `pantheon on` / `off` | enable/disable the US route |
| `pantheon heal` | re-point the SSH firewall rule at your current IP |
| `pantheon config <https-url>` | load `{"route": "http://user:pass@host:port"}` from a URL |
| `pantheon doctor [--heal]` | test the route, optionally heal and retest |

## What you need

1. Proxy credentials from your admin.
2. Your own Meta API key: <https://dev.meta.ai> -> API Keys.

## Files it touches

```
~/.config/muse/settings.json        proxy setting (mode 600)
~/.config/muse-vpn/proxy-url        saved route (mode 600)
~/.config/muse-vpn/heal.json        repair endpoint + token (mode 600)
~/.config/muse/auth.json            credential record (key in Keychain)
```

## Auto-heal

ISP addresses change, which breaks the SSH security-group rule. `pantheon heal`
POSTs to a small Lambda that rewrites that rule to the caller's IP; `setup` and
`doctor --heal` call it automatically when the network looks broken. It only
edits the SSH ingress rule — no shell without the private key. Lambda source:
`ops/lambda/pantheon_heal.py`.

## Troubleshooting

| symptom | cause | fix |
|---|---|---|
| `transport error` / `timed out` | route blocked or down | `pantheon doctor --heal` |
| `invalid_api_key` | bad/revoked key | create a new key, `pantheon setup` |
| `no visible models` | route not applied, or no plan on the account | `pantheon status`, check billing |
| `route FAILED` but heal OK | this network blocks the public port | use `pantheon doctor` from another network |
