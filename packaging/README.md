# Knowledge Manager — macOS packaging

Builds a standalone `Knowledge Manager.app` from the Quartz source in this repo. Colleagues can install it without having Node.js, npm, or any other tooling on their Macs.

## Build

```bash
./packaging/build-app.sh                  # builds for current arch
./packaging/build-app.sh --arch arm64     # explicit arm64 (Apple Silicon)
./packaging/build-app.sh --arch x64       # explicit x64 (Intel)
```

Output: `dist/Knowledge Manager.app` (~65 MB; bundled Node.js + Quartz source, no `node_modules` yet).

The first launch on each user's Mac runs `npm install` once into the user-space workspace (`~/Library/Application Support/Knowledge Manager/app/`), which takes ~2 minutes and needs internet.

## Distribute

Zip the bundle and share:

```bash
(cd dist && zip -qr "Knowledge Manager-arm64.zip" "Knowledge Manager.app")
```

Colleagues unzip, drag to `/Applications`, and the first time right-click → Open (so macOS Gatekeeper accepts the unsigned app).

## First-run UX

1. Prompts for the user's Obsidian vault folder.
2. Installs Quartz dependencies (first time only).
3. Starts the Quartz dev server on a free port (8080+).
4. Opens the default browser.

Subsequent launches: instant. If the server is already running, a dialog offers Open Browser or Stop.

## User-space state

All per-user state lives in `~/Library/Application Support/Knowledge Manager/`:

- `vault.path`   — chosen Obsidian vault
- `app/`         — Quartz workspace (source + node_modules)
- `server.pid`   — running server PID
- `server.port`  — active port
- `server.log`   — dev server logs
- `version`     — app version this workspace was built for (triggers re-sync on upgrade)

Deleting this folder is a clean reset.

## Upgrade flow

When you ship a new version of the app, bump `VERSION` in `packaging/build-app.sh`. On next launch, each user's workspace will be re-synced from the new bundle and `node_modules` rebuilt.
