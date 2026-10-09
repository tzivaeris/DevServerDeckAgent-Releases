# Dev Server Deck Agent Releases

Public binary releases for the Dev Server Deck local agent.

Source code is maintained separately. Download the latest verified build from the repository's [Releases](https://github.com/tzivaeris/DevServerDeckAgent-Releases/releases/latest) page.

## Latest version

Version: `2.15.25`

Expected release assets:

- `DevServerDeckAgent-win-x64.zip`
- `DevServerDeckAgent-linux-x64.zip`
- `DevServerDeckAgent-linux-arm64.zip` (as of `2.12.1`)

**macOS support is coming soon.** There is no supported macOS download at the moment. Apple Silicon builds are paused pending a code-signing fix, and a macOS zip that may be attached to some releases is an unsupported preview.

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
- `journalctl -u dev-server-deck-agent -n 200 --no-pager` - view recent history, e.g. right after an unexpected restart (systemd auto-restarts the agent if it crashes, and journald already captures whatever it printed before that happened)
- `sudo systemctl restart dev-server-deck-agent` - restart it manually

### Debug logging (as of `2.14.4`)

For deeper diagnosis than journald's own history covers (e.g. it's rotated past the point you need, or you're not running under systemd at all), the agent can mirror all of its own console output to a local file:

```bash
DevServerDeckAgent --debug=on   # enable - takes effect on the already-running agent, no restart needed
DevServerDeckAgent --debug=off  # disable
```

## Antivirus exclusion (recommended on every machine)

Add an exclusion for the agent's data folder - `%APPDATA%\dev-server-deck\` on Windows, `~/.dev-server-deck/` on Linux/macOS - in Windows Defender (or whatever antivirus/EDR tool runs on a managed Linux server). Do this **before** it ever flags anything, not just after.

Two things in that folder can trip a security tool's heuristics even though both are entirely legitimate:

- **The self-update helper** (`Apply-Update.ps1` on Windows, `apply-update.sh` on Linux/macOS - both static, shipped files sitting next to the agent executable itself, not generated at update time) kills the running agent process, replaces its executable, and relaunches it - behavior that looks exactly like a malware "dropper" to ML-based detection, and has been seen flagged as `Trojan:Win32/Bearfoos.A!ml` by Windows Defender. It is the agent updating itself, nothing else runs from that script. The Windows helper is code-signed and identical across every install/update (rather than freshly generated per update), which substantially reduces - but cannot entirely eliminate - the odds of a future false-positive flag.
- **Your Studio chat history** (`studio-sessions\`, `studio-history\`) is stored as many small AES-GCM encrypted files - to a scanner, encrypted data is indistinguishable from random noise, which is also a common ransomware-output signature. A security tool's "remediation" for an unrelated detection elsewhere in the same folder tree can end up deleting these as collateral cleanup, which is a real, confirmed way to lose your conversation history with no warning.

On Windows: Windows Security -> Virus & threat protection -> Manage settings -> Add or remove exclusions -> Folder -> `%APPDATA%\dev-server-deck`. If you ever see a detection there in Protection History, it's almost certainly this - restore it from quarantine rather than letting it be removed, and add the exclusion afterward so it doesn't recur.

Writes to `debug.log` next to the agent's other local data (`%APPDATA%\dev-server-deck\` on Windows, `~/.dev-server-deck/` on Linux), rotating to `debug.log.old` past 20 MB so leaving it on indefinitely can't fill the disk. On desktop, the same toggle is also available as a "Debug Logging" checkbox in the tray icon's menu.
