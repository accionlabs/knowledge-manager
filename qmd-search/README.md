# qmd-search

Standalone web UI for [tobi/qmd](https://github.com/tobi/qmd) — a local-first markdown search engine — wrapped around the same Obsidian vault that Knowledge Manager renders.

This is intentionally a **separate mini-app**, not integrated into the Quartz site. Once we're happy with the search quality + UX, the plan is to fold it into Knowledge Manager's sidebar.

## Prereq

- `qmd` installed and a collection configured against your vault. Verify with:
  ```sh
  qmd collection list
  qmd query "test" --json -n 1
  ```
- Node.js 18+ (already available on dev machines or via `~/.nvm`).

## Run

```sh
cd qmd-search
node server.mjs                       # default port 9090
node server.mjs --port 9100           # custom port
node server.mjs --qmd /full/path/qmd  # custom qmd binary
```

Then open http://localhost:9090.

## How it works

```
Browser ─── /api/search ───▶  Node server  ───▶  qmd query <q> --json  ───▶  result cards
```

- Backend has zero npm dependencies (Node built-ins only).
- Each query shells out to the `qmd` CLI; the JSON output is parsed and returned.
- The frontend converts qmd's `qmd://<collection>/path/foo.md` paths into Quartz URLs (`http://localhost:8080/path/foo`) so clicking a result opens the rendered note in Knowledge Manager (which must be running separately).

## Modes

- **Hybrid (best)** — `qmd query` with auto expansion + reranking
- **Keyword** — `qmd search` (BM25, no LLM)
- **Semantic** — `qmd vsearch` (vector only)

## Future integration

Once the standalone version is validated, we'll port the same `/api/search` endpoint into Quartz's existing sidebar search, swapping the FlexSearch backend for qmd. See `quartz/components/scripts/search.inline.ts`.
