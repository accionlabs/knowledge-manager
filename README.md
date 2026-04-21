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

## License

Quartz is MIT-licensed. See [LICENSE.txt](LICENSE.txt).
