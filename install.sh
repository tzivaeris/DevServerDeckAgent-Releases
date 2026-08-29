#!/bin/bash
# Dev Server Deck Agent - one-line installer for a headless Linux VPS.
# Usage: curl -fsSL <raw-url-to-this-file> | sudo bash -s -- --token=<AGENT_TOKEN>
set -euo pipefail

UNIT_NAME="dev-server-deck-agent.service"
INSTALL_DIR="/opt/dev-server-deck-agent"
BINARY_PATH="$INSTALL_DIR/DevServerDeckAgent"
DOWNLOAD_URL="https://github.com/tzivaeris/DevServerDeckAgent-Releases/releases/latest/download/DevServerDeckAgent-linux-x64.zip"

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer must run as root (writes to /etc/systemd/system and $INSTALL_DIR)." >&2
  echo "Try: curl -fsSL <url> | sudo bash -s -- --token=<AGENT_TOKEN>" >&2
  exit 1
fi

if [ ! -d /run/systemd/system ]; then
  echo "systemd was not detected on this machine (no /run/systemd/system)." >&2
  echo "This installer only supports systemd-based distributions." >&2
  exit 1
fi

for cmd in curl unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required but was not found. Install it first, e.g.: apt-get install -y $cmd" >&2
    exit 1
  fi
done

AGENT_TOKEN=""
CLI_USER=""
for arg in "$@"; do
  case "$arg" in
    --token=*) AGENT_TOKEN="${arg#--token=}" ;;
    --user=*) CLI_USER="${arg#--user=}" ;;
  esac
done
if [ -z "$AGENT_TOKEN" ]; then
  echo "Usage: $0 --token=<AGENT_TOKEN>" >&2
  echo "Get an Agent Token from Dev Server Deck's dashboard: Account & Billing -> Agent Tokens." >&2
  exit 1
fi

# Unit-file ExecStart= lines have their own word-splitting and %-specifier
# expansion rules - this is not a shell command line, so bash quoting does
# not protect it. A token containing whitespace would silently split into
# extra argv elements, and a literal % would trigger systemd specifier
# expansion. Reject anything outside a safe character set up front.
if ! [[ "$AGENT_TOKEN" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "The provided --token value contains unexpected characters. Agent Tokens should only contain letters, digits, dots, dashes, and underscores." >&2
  exit 1
fi

# The service must run as a real, non-root user - registered project
# commands run as whatever user the agent runs as, and running arbitrary
# project commands as root on a VPS would be an avoidable privilege-
# escalation surface. We never fall back to root implicitly (e.g. via
# whoami) - if neither sudo nor --user tells us who that user is, fail
# loudly instead of silently installing a root-run service.
RUN_AS_USER="${SUDO_USER:-$CLI_USER}"
if [ -z "$RUN_AS_USER" ]; then
  echo "Could not determine which non-root user the agent should run as." >&2
  echo "Either run this installer via sudo as a real login user, e.g.:" >&2
  echo "  curl -fsSL <url> | sudo bash -s -- --token=<AGENT_TOKEN>" >&2
  echo "or, if you are genuinely running as root with no other user available, pass --user explicitly:" >&2
  echo "  curl -fsSL <url> | bash -s -- --token=<AGENT_TOKEN> --user=<username>" >&2
  exit 1
fi
# Same injection surface as AGENT_TOKEN above (this value also lands in the
# unit file's own ExecStart=/User= directives) - --user is operator-supplied,
# so validate it the same way rather than trusting it's a real username.
if ! [[ "$RUN_AS_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "The --user value contains unexpected characters. Usernames should only contain letters, digits, dots, dashes, and underscores." >&2
  exit 1
fi
RUN_AS_HOME=$(getent passwd "$RUN_AS_USER" | cut -d: -f6)
if [ -z "$RUN_AS_HOME" ]; then
  echo "Could not resolve a home directory for user $RUN_AS_USER." >&2
  exit 1
fi

echo "Installing Dev Server Deck Agent for user $RUN_AS_USER..."

mkdir -p "$INSTALL_DIR"
TMP_ZIP=$(mktemp)
trap 'rm -f "$TMP_ZIP"' EXIT
echo "Downloading latest Linux build..."
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_ZIP"
unzip -o -q "$TMP_ZIP" -d "$INSTALL_DIR"
# The extracted binary's name is tied to the Local Agent repo's own
# scripts/package.js (its `linux.binary` config value), which names the
# built Linux binary "DevServerDeckAgent-linux-x64" rather than the stable
# "DevServerDeckAgent" name used below in ExecStart= and documentation.
# Extract under that real name, then move it into the stable position.
EXTRACTED_BINARY="$INSTALL_DIR/DevServerDeckAgent-linux-x64"
if [ ! -f "$EXTRACTED_BINARY" ]; then
  echo "Expected binary not found at $EXTRACTED_BINARY after extracting the release zip." >&2
  echo "The release archive's internal layout may have changed - check its contents." >&2
  exit 1
fi
mv "$EXTRACTED_BINARY" "$BINARY_PATH"
chmod +x "$BINARY_PATH"
chown -R "$RUN_AS_USER" "$INSTALL_DIR"

# The agent token must not appear on the process command line (--token=...
# would be world-readable via /proc/<pid>/cmdline or `ps aux` regardless of
# the unit file's own permissions). Instead, write it to a separate,
# root-owned, mode-600 environment file and have the unit load it via
# EnvironmentFile=. The agent already resolves its token from the
# AGENT_TOKEN environment variable, so no agent-side change is needed.
# `install -m 600 /dev/null` creates the file at the restricted mode
# up front, so there is never a window where it's world-readable.
ENV_FILE="/etc/dev-server-deck-agent.env"
install -m 600 /dev/null "$ENV_FILE"
echo "AGENT_TOKEN=$AGENT_TOKEN" > "$ENV_FILE"

cat > "/etc/systemd/system/$UNIT_NAME" <<UNIT
[Unit]
Description=Dev Server Deck Agent
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BINARY_PATH
EnvironmentFile=$ENV_FILE
Environment=DSD_SYSTEMD_UNIT_NAME=$UNIT_NAME
Restart=always
RestartSec=5
User=$RUN_AS_USER
KillMode=process

[Install]
WantedBy=multi-user.target
UNIT
chmod 600 "/etc/systemd/system/$UNIT_NAME"

# The self-update helper is spawned detached (new session) but stays in the
# unit's cgroup - KillMode=process above keeps systemd from SIGTERMing it
# when the main agent process exits for a self-update. Restart=always (not
# on-failure) is required because the self-update route ends with a clean
# exit(0), which on-failure would never treat as restart-worthy.
#
# The helper's rollback path needs to `systemctl restart` this unit as the
# non-root service user, which polkit would otherwise deny with no visible
# error. Grant exactly this one user permission to manage exactly this one
# unit, nothing broader.
cat > "/etc/polkit-1/rules.d/49-dev-server-deck-agent.rules" <<POLKIT
polkit.addRule(function(action, subject) {
  if (action.id == "org.freedesktop.systemd1.manage-units" &&
      action.lookup("unit") == "$UNIT_NAME" &&
      subject.user == "$RUN_AS_USER") {
    return polkit.Result.YES;
  }
});
POLKIT

echo "Enabling and starting $UNIT_NAME..."
systemctl daemon-reload
systemctl enable --now "$UNIT_NAME"

echo ""
echo "Done. Check status with: systemctl status $UNIT_NAME"
echo "View logs with: journalctl -u $UNIT_NAME -f"
