# Dev Server Deck Agent Releases

Public binary releases for the Dev Server Deck local agent.

Source code is maintained separately. Download the latest verified build from the repository's [Releases](https://github.com/tzivaeris/DevServerDeckAgent-Releases/releases/latest) page.

## Latest version

Version: `2.12.33`

Expected release assets:

- `DevServerDeckAgent-win-x64.zip`
- `DevServerDeckAgent-linux-x64.zip`
- `DevServerDeckAgent-linux-arm64.zip` (as of `2.12.1`)
- `DevServerDeckAgent-macos-x64.zip`
- `DevServerDeckAgent-macos-arm64.zip` (temporarily not published as of `2.1.4` - macOS arm64 builds are paused pending a code-signing fix; the last available arm64 build is attached to the `v2.0.6` release)

Release ZIPs are attached to GitHub Releases and are intentionally not committed to this repository.

## Recommended VPS specs

If you're running the agent on a cloud VPS (not your own desktop), size it for at least:

- **2 vCPU / 2 GB RAM** minimum, **4 GB RAM** recommended if you use Codex regularly or run more than one project's dev server on the same box. A 1 GB instance (e.g. AWS/GCP's smallest "micro" tiers) is too tight - it can get its own agent process killed outright by the kernel's out-of-memory killer during a real Codex turn, losing that turn's entire session with no way to recover it.
- **Swap space** (1-2 GB), even on a box that otherwise meets the RAM recommendation above. Most stock VPS images ship with none by default; adding it costs nothing and turns a rare memory spike into "briefly slower" instead of a killed process. On Debian/Ubuntu:
  ```bash
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  ```

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
