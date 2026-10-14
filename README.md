# Dev Server Deck Agent Releases

Public binary releases for the Dev Server Deck local agent.

Source code is maintained separately. Download the latest verified build from the repository's [Releases](https://github.com/tzivaeris/DevServerDeckAgent-Releases/releases/latest) page.

## Latest version

Version: `2.15.34`

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

<a id="power-actions"></a>
## Power actions (restart/shutdown) (as of `2.15.31`)

The dashboard's Machines tab has "Restart machine"/"Shut down machine" buttons per registered machine. The agent runs unprivileged on every platform (no Windows Service, no root) and does not attempt any elevation of its own - it just invokes the OS's own shutdown command and reports whatever it says.

- **Windows:** works out of the box, no setup needed. "Shut down the system" is a right granted to the Users group by default in Windows' local security policy, so a normal (non-admin) process can restart/shut down the local machine without a UAC prompt.
- **Linux:** restarting/powering off genuinely requires root, and the agent has no way to prompt for a sudo password unattended - clicking these buttons will fail with a permission error until you grant a narrowly-scoped, passwordless sudo rule for just the `shutdown` command (not full sudo access):

  ```bash
  sudo visudo -f /etc/sudoers.d/devserverdeck-agent
  ```

  Add this one line (replace `youruser` with whichever user account the agent actually runs as on that machine - `whoami` while it's running, or check the systemd unit's `User=` line if installed via the headless-VPS installer above):

  ```
  youruser ALL=(root) NOPASSWD: /usr/sbin/shutdown
  ```

  If `shutdown` isn't at `/usr/sbin/shutdown` on your distro, confirm the real path first with `which shutdown` and use that instead. Save and exit - no restart of the agent is needed, the next click will just work.

<a id="windows-service-mode"></a>
## Windows Service mode (run the agent before login)

By default the agent runs as a tray app in whichever user's desktop session is logged in - if nobody is signed in (e.g. right after a reboot), it isn't running at all. Windows Service mode is an opt-in, per-machine alternative: the agent runs as a Windows Service instead, starting at boot regardless of whether anyone ever logs in. It's fully reversible, and your Agent Token is preserved across the switch either way - neither direction requires re-pairing the machine.

When someone is actively logged into the machine's console session, service mode behaves identically to tray mode: project commands run impersonating that logged-in user, with that user's own permissions and environment. Service mode only changes what happens when nobody is logged in - which is governed by a separate toggle, below.

### Installing the service

Both scripts ship inside the Windows release zip, next to `DevServerDeckAgent.exe` (same folder as `Apply-Update.ps1` and `Start-Silently.vbs`), and are code-signed like the rest of the agent's own self-update tooling. Neither can run un-elevated.

1. Extract `DevServerDeckAgent-win-x64.zip` if you haven't already.
2. Right-click `scripts\Install-Service.ps1` -> "Run with PowerShell" as Administrator (or open an elevated PowerShell prompt and run `.\Install-Service.ps1` from the `scripts` folder). This can't be done remotely from the dashboard - installing a Windows Service requires Administrator rights on that machine.

`Install-Service.ps1` does the following, in order: disables the tray app's autostart and stops any running tray instance (tray mode and service mode are mutually exclusive - never both running at once); migrates the tray app's Agent Token into `%ProgramData%\dev-server-deck` (a service account can't reach the tray app's per-user `%APPDATA%` copy or the OS Credential Manager); registers the service via `sc.exe create DevServerDeckAgent binPath= "<path-to-exe> --service-mode" start= auto`; and starts it with `sc.exe start DevServerDeckAgent`.

Confirm it's running:

```powershell
sc.exe query DevServerDeckAgent
```

A healthy install shows `STATE : 4  RUNNING`. If it shows `STOPPED` or the query fails with "the specified service does not exist", the install didn't complete - re-run `Install-Service.ps1` and check its console output (it also writes a JSON result to `%ProgramData%\dev-server-deck\install-result.json`) for the specific failure.

### Switching back to tray mode

Right-click `scripts\Uninstall-Service.ps1` -> "Run with PowerShell" as Administrator, from the same folder. It stops and deletes the `DevServerDeckAgent` service (idempotent - already-stopped/already-deleted is treated as success, not an error) and restores the tray app's autostart registry entry, pointing at `Start-Silently.vbs` next to the agent executable. It deliberately does **not** delete `%ProgramData%\dev-server-deck` - the migrated credential stays in place so switching back to tray mode needs zero re-pairing.

Afterward, `sc.exe query DevServerDeckAgent` should fail with "the specified service does not exist" - that's the expected, successful outcome.

### The SYSTEM toggle

In the dashboard's account settings, service-mode machines expose a toggle: "Allow starting projects as SYSTEM when nobody's logged in." It's **off by default**.

With it off, starting a project while nobody is logged into that machine's console is rejected outright - there's no user context to run the command under, and the agent never silently falls back to anything broader. Turning it on allows project commands to run under the SYSTEM account itself when there's no logged-in user to impersonate. This is a real tradeoff: SYSTEM has broader privileges on the machine than an ordinary user account, so enabling it trades some per-user isolation for the ability to start projects on a machine nobody is sitting at. Leave it off unless you specifically need that.

## Antivirus exclusion (recommended on every machine)

Add an exclusion for the agent's data folder - `%APPDATA%\dev-server-deck\` on Windows, `~/.dev-server-deck/` on Linux/macOS - in Windows Defender (or whatever antivirus/EDR tool runs on a managed Linux server). Do this **before** it ever flags anything, not just after.

Two things in that folder can trip a security tool's heuristics even though both are entirely legitimate:

- **The self-update helper** (`Apply-Update.ps1` on Windows, `apply-update.sh` on Linux/macOS - both static, shipped files sitting next to the agent executable itself, not generated at update time) kills the running agent process, replaces its executable, and relaunches it - behavior that looks exactly like a malware "dropper" to ML-based detection, and has been seen flagged as `Trojan:Win32/Bearfoos.A!ml` by Windows Defender. It is the agent updating itself, nothing else runs from that script. The Windows helper is code-signed and identical across every install/update (rather than freshly generated per update), which substantially reduces - but cannot entirely eliminate - the odds of a future false-positive flag.
- **Your Studio chat history** (`studio-sessions\`, `studio-history\`) is stored as many small AES-GCM encrypted files - to a scanner, encrypted data is indistinguishable from random noise, which is also a common ransomware-output signature. A security tool's "remediation" for an unrelated detection elsewhere in the same folder tree can end up deleting these as collateral cleanup, which is a real, confirmed way to lose your conversation history with no warning.

On Windows: Windows Security -> Virus & threat protection -> Manage settings -> Add or remove exclusions -> Folder -> `%APPDATA%\dev-server-deck`. If you ever see a detection there in Protection History, it's almost certainly this - restore it from quarantine rather than letting it be removed, and add the exclusion afterward so it doesn't recur.

Writes to `debug.log` next to the agent's other local data (`%APPDATA%\dev-server-deck\` on Windows, `~/.dev-server-deck/` on Linux), rotating to `debug.log.old` past 20 MB so leaving it on indefinitely can't fill the disk. On desktop, the same toggle is also available as a "Debug Logging" checkbox in the tray icon's menu.
