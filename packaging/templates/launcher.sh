#!/bin/bash
# Knowledge Manager launcher.
# - First launch: prompts for vault folder, copies app source to user space, installs deps.
# - Subsequent launches: starts the Quartz dev server and opens the browser.
# - If server is already running: shows a dialog with Open / Stop actions.

set -e

# ---------- Paths ----------
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NODE_HOME="$APP_DIR/Resources/node"
BUNDLED_APP="$APP_DIR/Resources/app"

SUPPORT_DIR="$HOME/Library/Application Support/Knowledge Manager"
USER_APP="$SUPPORT_DIR/app"
PID_FILE="$SUPPORT_DIR/server.pid"
PORT_FILE="$SUPPORT_DIR/server.port"
VAULT_FILE="$SUPPORT_DIR/vault.path"
LOG_FILE="$SUPPORT_DIR/server.log"
VERSION_FILE="$SUPPORT_DIR/version"

BUNDLE_VERSION=$(defaults read "$APP_DIR/Info" CFBundleVersion 2>/dev/null || echo "0")
DEFAULT_PORT=8080

mkdir -p "$SUPPORT_DIR"
export PATH="$NODE_HOME/bin:$PATH"

die() {
  osascript -e "display dialog \"$1\" buttons {\"OK\"} with icon stop" >/dev/null 2>&1
  exit 1
}

notify() {
  osascript -e "display notification \"$1\" with title \"Knowledge Manager\"" >/dev/null 2>&1
}

# ---------- Vault picker (first run) ----------
if [ ! -f "$VAULT_FILE" ]; then
  VAULT_PATH=$(osascript <<'EOF' 2>/dev/null
tell application "System Events"
  activate
  set theFolder to choose folder with prompt "Select your Obsidian vault folder (the folder that contains your notes)"
  return POSIX path of theFolder
end tell
EOF
  )
  [ -z "$VAULT_PATH" ] && exit 0
  VAULT_PATH="${VAULT_PATH%/}"
  echo "$VAULT_PATH" > "$VAULT_FILE"
fi

VAULT_PATH=$(cat "$VAULT_FILE")
if [ ! -d "$VAULT_PATH" ]; then
  rm -f "$VAULT_FILE"
  die "Vault folder not found: $VAULT_PATH\n\nIt has been unset — please re-launch Knowledge Manager to select your vault again."
fi

# ---------- Server already running? ----------
if [ -f "$PID_FILE" ] && [ -f "$PORT_FILE" ]; then
  EXISTING_PID=$(cat "$PID_FILE")
  EXISTING_PORT=$(cat "$PORT_FILE")
  if ps -p "$EXISTING_PID" > /dev/null 2>&1; then
    CHOICE=$(osascript <<EOF 2>/dev/null
tell application "System Events"
  activate
  set dialogResult to display dialog "Knowledge Manager is running at http://localhost:$EXISTING_PORT" buttons {"Stop", "Open Browser"} default button "Open Browser" with title "Knowledge Manager"
  return button returned of dialogResult
end tell
EOF
    )
    case "$CHOICE" in
      "Stop")
        kill "$EXISTING_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$EXISTING_PID" 2>/dev/null || true
        rm -f "$PID_FILE" "$PORT_FILE"
        notify "Server stopped."
        ;;
      "Open Browser")
        open "http://localhost:$EXISTING_PORT"
        ;;
    esac
    exit 0
  else
    rm -f "$PID_FILE" "$PORT_FILE"
  fi
fi

# ---------- Sync app source to user space ----------
STORED_VERSION=""
[ -f "$VERSION_FILE" ] && STORED_VERSION=$(cat "$VERSION_FILE")

if [ ! -d "$USER_APP" ] || [ "$STORED_VERSION" != "$BUNDLE_VERSION" ]; then
  notify "Preparing workspace..."
  rm -rf "$USER_APP"
  mkdir -p "$USER_APP"
  # Copy bundled Quartz source (no node_modules) into user space.
  # Use ditto so extended attrs are preserved and hidden files are copied.
  ditto "$BUNDLED_APP/" "$USER_APP/"
  echo "$BUNDLE_VERSION" > "$VERSION_FILE"
  # Force reinstall since source changed.
  rm -rf "$USER_APP/node_modules"
fi

# ---------- Link vault ----------
ln -sfn "$VAULT_PATH" "$USER_APP/content"

# ---------- Install deps on first launch ----------
cd "$USER_APP"
if [ ! -d "node_modules" ]; then
  osascript -e 'display notification "Installing dependencies (first launch, ~2 min, requires internet)" with title "Knowledge Manager"' >/dev/null 2>&1
  if ! "$NODE_HOME/bin/npm" install --prefer-offline --no-audit --no-fund --silent > "$LOG_FILE" 2>&1; then
    die "Failed to install dependencies.\n\nCheck your internet connection and try again.\n\nLog: $LOG_FILE"
  fi
fi

# ---------- Pick free ports for HTTP + WebSocket live-reload ----------
PORT=$DEFAULT_PORT
while lsof -iTCP:$PORT -sTCP:LISTEN > /dev/null 2>&1; do
  PORT=$((PORT + 1))
  [ $PORT -gt 8100 ] && die "No free HTTP port found between 8080 and 8100."
done

WS_PORT=3001
while lsof -iTCP:$WS_PORT -sTCP:LISTEN > /dev/null 2>&1; do
  WS_PORT=$((WS_PORT + 1))
  [ $WS_PORT -gt 3100 ] && die "No free WebSocket port found between 3001 and 3100."
done

# ---------- Start server as child of this launcher ----------
"$NODE_HOME/bin/npx" quartz build --serve --port "$PORT" --wsPort "$WS_PORT" > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"
echo "$PORT" > "$PORT_FILE"

# Make sure we kill the server if the launcher is asked to quit (Dock → Quit,
# Cmd+Q, logout, system shutdown, etc.).
cleanup() {
  if ps -p "$SERVER_PID" > /dev/null 2>&1; then
    kill "$SERVER_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE" "$PORT_FILE"
  exit 0
}
trap cleanup TERM INT HUP QUIT

# ---------- Wait for readiness, open browser ----------
READY=0
for i in $(seq 1 90); do
  if curl -fs "http://localhost:$PORT/" > /dev/null 2>&1; then
    READY=1
    break
  fi
  if ! ps -p "$SERVER_PID" > /dev/null 2>&1; then
    rm -f "$PID_FILE" "$PORT_FILE"
    die "Server failed to start. See log: $LOG_FILE"
  fi
  sleep 1
done

if [ $READY -ne 1 ]; then
  cleanup
  die "Server did not respond within 90 seconds. See log: $LOG_FILE"
fi

open "http://localhost:$PORT"
notify "Running at http://localhost:$PORT — quit from the Dock to stop"

# Stay alive as long as the server is alive so the Dock shows the app.
wait "$SERVER_PID"
cleanup
