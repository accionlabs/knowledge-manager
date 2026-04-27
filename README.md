# Knowledge Manager

Render an Obsidian vault as a browsable, print-friendly website. Packaged as a macOS `.app` so non-technical colleagues can install it in one step.

## For end users

Go to the **[download page](https://accionlabs.github.io/knowledge-manager/)** — zero dependencies, drag-and-drop install.

## For developers

This repo is based on [Quartz v4](https://quartz.jzhao.xyz/) with local customizations (print CSS, mermaid fixes, Accion branding, explorer tweaks, table styling) and a macOS packaging layer that bundles Node.js so colleagues don't need to install anything.

### Build locally

```bash
npm install
npx quartz build --serve
# Server at http://localhost:8080, watching ./content
```

Point `./content` at your Obsidian vault (symlink):

```bash
ln -sfn "/path/to/vault" content
```

### Build the `.app` bundle

```bash
./packaging/build-app.sh               # current arch
./packaging/build-app.sh --arch arm64  # Apple Silicon
./packaging/build-app.sh --arch x64    # Intel
```

Output lands in `dist/`. See [`packaging/README.md`](packaging/README.md) for details.

### Release

CI (`.github/workflows/release.yml`) automatically builds both architectures and publishes a GitHub Release when you push a `v*` tag:

```bash
git tag v1.0.0 && git push --tags
```

The same workflow deploys the download page (`site/`) to GitHub Pages on every push to `main`.

## Optional: semantic search via qmd

The default sidebar search is Quartz's built-in FlexSearch — fast, offline, no extra setup. If you want **hybrid (BM25 + vector + LLM rerank) search** over your vault, you can plug in [tobi/qmd](https://github.com/tobi/qmd).

### One-time setup

```bash
# 1. Install qmd globally (Node ≥ 18 required)
npm install -g @tobilu/qmd

# 2. Index your vault (replace the path with your own)
qmd collection add "/path/to/your/Obsidian/vault" --name content

# 3. Generate vector embeddings (~5-10 min on first run; downloads a GGUF model)
qmd embed
```

### Per-launch: start the bridge server

The Knowledge Manager UI talks to qmd via a tiny HTTP shim that ships in this repo (`qmd-search/`):

```bash
cd ~/knowledge-manager/qmd-search
node server.mjs            # default: http://localhost:9090
```

Leave it running in a Terminal tab. It shells out to `qmd query` and returns JSON.

### Wire qmd into the sidebar

Edit `quartz.layout.ts`. In both `defaultContentPageLayout` and `defaultListPageLayout`, replace:

```ts
Component: Component.Search(),
```

with:

```ts
Component: Component.Search({
  backend: "qmd",
  qmdEndpoint: "http://localhost:9090",
}),
```

Restart Quartz — now the sidebar search queries qmd. If the qmd-search server isn't running, the panel shows a friendly "qmd unreachable" message.

### Standalone qmd-search UI

Even without integrating into Quartz, you can use the standalone search page at `http://localhost:9090` once the bridge server is up. See [`qmd-search/README.md`](qmd-search/README.md) for details.

## License

Quartz is MIT-licensed. See [LICENSE.txt](LICENSE.txt).
