#!/bin/bash
# Knowledge Manager — install + run
#
# One command to set up Node (via nvm, user-scoped, no sudo), clone the
# Knowledge Manager repo, install deps, and start the Quartz dev server
# against your Obsidian vault.
#
# First run: installs everything, prompts for your vault, starts the server.
# Subsequent runs: just starts the server (Ctrl+C to stop).
#
# Paste into Terminal:
#   curl -fsSL https://accionlabs.github.io/knowledge-manager/install.sh | bash
# or
#   bash install.sh
#
# Requires: macOS, Terminal, git (macOS ships with it via Command Line Tools).

set -e

REPO_URL="https://github.com/accionlabs/knowledge-manager.git"
INSTALL_DIR="$HOME/knowledge-manager"
NODE_MAJOR=22
NVM_VERSION="v0.39.7"
DEFAULT_PORT=8080
VAULT_FILE="$INSTALL_DIR/.vault-path"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
info() { echo "${BOLD}==>${RESET} $*"; }
note() { echo "${DIM}$*${RESET}"; }
ok()   { echo "${GREEN}✓${RESET} $*"; }
err()  { echo "${RED}✗${RESET} $*" >&2; }

# --- Prereq: git -----------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  err "git is not installed."
  echo "   Run this in Terminal to install Command Line Tools: xcode-select --install"
  exit 1
fi

# --- Node (system or nvm) --------------------------------------------------
HAVE_NODE=0
if command -v node >/dev/null 2>&1; then
  CURRENT_MAJOR=$(node -v | sed -E 's/^v([0-9]+).*/\1/')
  if [ "$CURRENT_MAJOR" -ge "$NODE_MAJOR" ]; then
    HAVE_NODE=1
    ok "Using system Node $(node -v)"
  fi
fi

if [ $HAVE_NODE -eq 0 ]; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    info "Installing nvm (Node Version Manager) in $NVM_DIR"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  fi
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"

  if ! nvm which "$NODE_MAJOR" >/dev/null 2>&1; then
    info "Installing Node.js $NODE_MAJOR (LTS)"
    nvm install "$NODE_MAJOR" --lts
  fi
  nvm use "$NODE_MAJOR" >/dev/null
  ok "Using nvm Node $(node -v)"
fi

# --- Clone or update repo --------------------------------------------------
if [ ! -d "$INSTALL_DIR/.git" ]; then
  info "Cloning Knowledge Manager into $INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
else
  info "Updating Knowledge Manager in $INSTALL_DIR"
  if ! git -C "$INSTALL_DIR" pull --quiet --ff-only 2>/dev/null; then
    note "  (couldn't fast-forward — continuing with current version)"
  fi
fi

cd "$INSTALL_DIR"

# --- Dependencies ----------------------------------------------------------
if [ ! -d "node_modules" ]; then
  info "Installing dependencies (~1 min, first run only)"
  npm install --no-audit --no-fund
fi

# --- Vault prompt ----------------------------------------------------------
if [ ! -f "$VAULT_FILE" ]; then
  echo
  echo "${BOLD}Select your Obsidian vault folder.${RESET}"
  echo "Tip: drag the folder from Finder into Terminal to paste its path."
  printf "${BOLD}Vault path:${RESET} "
  # Read from /dev/tty so this works even when the script is piped to bash.
  read -r VAULT_PATH < /dev/tty
  # Strip surrounding quotes (Finder drag wraps in single quotes) + trailing slash.
  VAULT_PATH="${VAULT_PATH#\'}"; VAULT_PATH="${VAULT_PATH%\'}"
  VAULT_PATH="${VAULT_PATH#\"}"; VAULT_PATH="${VAULT_PATH%\"}"
  VAULT_PATH="${VAULT_PATH%/}"
  if [ ! -d "$VAULT_PATH" ]; then
    err "Not a folder: $VAULT_PATH"
    exit 1
  fi
  echo "$VAULT_PATH" > "$VAULT_FILE"
fi

VAULT_PATH=$(cat "$VAULT_FILE")
if [ ! -d "$VAULT_PATH" ]; then
  err "Saved vault path no longer exists: $VAULT_PATH"
  echo "   Reset with: rm \"$VAULT_FILE\" && $0"
  exit 1
fi
ln -sfn "$VAULT_PATH" "$INSTALL_DIR/content"
ok "Vault: $VAULT_PATH"

# --- Pick free ports -------------------------------------------------------
PORT=$DEFAULT_PORT
while lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; do
  PORT=$((PORT + 1))
  [ $PORT -gt 8100 ] && { err "No free HTTP port between 8080-8100"; exit 1; }
done
WS_PORT=3001
while lsof -iTCP:$WS_PORT -sTCP:LISTEN >/dev/null 2>&1; do
  WS_PORT=$((WS_PORT + 1))
  [ $WS_PORT -gt 3100 ] && { err "No free WebSocket port between 3001-3100"; exit 1; }
done

# --- Start server ----------------------------------------------------------
URL="http://localhost:$PORT"
info "Starting Knowledge Manager at $URL"
note "    (WebSocket live-reload on port $WS_PORT)"
echo
npx quartz build --serve --port "$PORT" --wsPort "$WS_PORT" &
QUARTZ_PID=$!

trap 'kill "$QUARTZ_PID" 2>/dev/null; exit 0' INT TERM

# Wait for HTTP readiness, then open the browser.
for _ in $(seq 1 90); do
  if curl -fs "$URL/" >/dev/null 2>&1; then
    open "$URL"
    break
  fi
  if ! kill -0 "$QUARTZ_PID" 2>/dev/null; then
    err "Server exited during startup — scroll up for the error."
    exit 1
  fi
  sleep 1
done

echo
ok "Running at $URL"
note "Press Ctrl+C to stop."
echo
wait "$QUARTZ_PID"
