# Dev Server Deck Agent Releases

Public binary releases for the Dev Server Deck local agent.

Source code is maintained separately. Download the latest verified build from the repository's [Releases](https://github.com/tzivaeris/DevServerDeckAgent-Releases/releases/latest) page.

## Latest version

Version: `2.12.7`

Expected release assets:

- `DevServerDeckAgent-win-x64.zip`
- `DevServerDeckAgent-linux-x64.zip`
- `DevServerDeckAgent-linux-arm64.zip` (as of `2.12.1`)
- `DevServerDeckAgent-macos-x64.zip`
- `DevServerDeckAgent-macos-arm64.zip` (temporarily not published as of `2.1.4` - macOS arm64 builds are paused pending a code-signing fix; the last available arm64 build is attached to the `v2.0.6` release)

Release ZIPs are attached to GitHub Releases and are intentionally not committed to this repository.

## Headless Linux (VPS) install

For a bare Linux server with no desktop environment, a one-line installer sets up the agent as a systemd service that starts on boot and restarts automatically if it ever crashes:

```bash
curl -fsSL https://raw.githubusercontent.com/tzivaeris/DevServerDeckAgent-Releases/main/install.sh | sudo bash -s -- --token=<AGENT_TOKEN>
```

Get an Agent Token from the dashboard: Account & Billing -> Agent Tokens. Requires a systemd-based distribution (Ubuntu, Debian, and most current VPS images qualify) and root/sudo. Both x86_64 and arm64 (aarch64) are supported - the installer detects your CPU architecture automatically, so the same command works on either.

Useful commands afterward:
- `systemctl status dev-server-deck-agent` - check it's running
- `journalctl -u dev-server-deck-agent -f` - follow its logs
- `sudo systemctl restart dev-server-deck-agent` - restart it manually
