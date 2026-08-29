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
if [ ! -f "$BINARY_PATH" ]; then
  echo "Expected binary not found at $BINARY_PATH after extracting the release zip." >&2
  echo "The release archive's internal layout may have changed - check its contents." >&2
  exit 1
fi
chmod +x "$BINARY_PATH"
chown -R "$RUN_AS_USER" "$INSTALL_DIR"

cat > "/etc/systemd/system/$UNIT_NAME" <<UNIT
[Unit]
Description=Dev Server Deck Agent
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BINARY_PATH --token=$AGENT_TOKEN
Environment=DSD_SYSTEMD_UNIT_NAME=$UNIT_NAME
Restart=on-failure
RestartSec=5
User=$RUN_AS_USER

[Install]
WantedBy=multi-user.target
UNIT
chmod 600 "/etc/systemd/system/$UNIT_NAME"

echo "Enabling and starting $UNIT_NAME..."
systemctl daemon-reload
systemctl enable --now "$UNIT_NAME"

echo ""
echo "Done. Check status with: systemctl status $UNIT_NAME"
echo "View logs with: journalctl -u $UNIT_NAME -f"
