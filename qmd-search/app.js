// qmd-search frontend. Calls /api/search and renders results.

const QUARTZ_BASE = "http://localhost:8080"

const $q = document.getElementById("q")
const $mode = document.getElementById("mode")
const $form = document.getElementById("search-form")
const $results = document.getElementById("results")
const $state = document.getElementById("state")
const $status = document.getElementById("status")

// Mirrors quartz/util/path.ts -> sluggify(): replaces spaces, &, %, etc. so we
// can map qmd's file paths to the URLs Quartz emits.
function sluggify(s) {
  return s
    .split("/")
    .map((seg) =>
      seg
        .replace(/\s/g, "-")
        .replace(/&/g, "-and-")
        .replace(/%/g, "-percent")
        .replace(/\?/g, "")
        .replace(/#/g, ""),
    )
    .join("/")
    .replace(/\/$/, "")
}

// "qmd://content/projects/Foo/Bar.md"
//    → "/projects/Foo/Bar"
//    → "http://localhost:8080/projects/Foo/Bar"
function quartzUrl(qmdFile) {
  // Strip the qmd:// scheme + collection-name prefix.
  const m = qmdFile.match(/^qmd:\/\/[^/]+\/(.+)$/)
  let rel = m ? m[1] : qmdFile
  // Strip a trailing .md if present.
  rel = rel.replace(/\.md$/i, "")
  return `${QUARTZ_BASE}/${sluggify(rel)}`
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

// qmd snippets sometimes contain @@ markers for hunk context. Strip those so
// the user sees clean prose.
function cleanSnippet(s) {
  if (!s) return ""
  return s
    .split("\n")
    .filter((line) => !/^@@.*@@\s*\(.*\)$/.test(line))
    .join("\n")
    .trim()
}

function render(results) {
  $results.innerHTML = ""
  if (!results.length) {
    $state.textContent = "No matches."
    return
  }
  $state.textContent = `${results.length} result${results.length === 1 ? "" : "s"}`
  for (const r of results) {
    const li = document.createElement("li")
    li.className = "result"
    const title = r.title || r.file?.split("/").pop() || "Untitled"
    const score = typeof r.score === "number" ? r.score.toFixed(2) : ""
    const url = quartzUrl(r.file)

    li.innerHTML = `
      <div class="result-head">
        <a class="title" href="${url}" target="_blank">${escapeHtml(title)}</a>
        ${score ? `<span class="score" title="qmd score">${score}</span>` : ""}
      </div>
      <div class="path">${escapeHtml(r.file)}</div>
      ${r.context ? `<div class="context">${escapeHtml(r.context)}</div>` : ""}
      <pre class="snippet">${escapeHtml(cleanSnippet(r.snippet))}</pre>
    `
    $results.appendChild(li)
  }
}

let inflight = null
async function runSearch() {
  const q = $q.value.trim()
  if (!q) {
    $results.innerHTML = ""
    $state.textContent = "Type something to search."
    return
  }

  if (inflight) inflight.abort()
  const ctrl = new AbortController()
  inflight = ctrl

  $state.textContent = "Searching…"
  try {
    const u = new URL(window.location.origin + "/api/search")
    u.searchParams.set("q", q)
    u.searchParams.set("mode", $mode.value)
    u.searchParams.set("n", "20")
    const res = await fetch(u, { signal: ctrl.signal })
    const data = await res.json()
    if (!res.ok) {
      $state.textContent = `Error: ${data.error || res.status}`
      return
    }
    render(data.results || [])
  } catch (err) {
    if (err.name === "AbortError") return
    $state.textContent = `Error: ${err.message}`
  } finally {
    if (inflight === ctrl) inflight = null
  }
}

$form.addEventListener("submit", (e) => {
  e.preventDefault()
  runSearch()
})

$mode.addEventListener("change", () => {
  if ($q.value.trim()) runSearch()
})

// Light status check on load — confirms the qmd CLI is reachable.
;(async () => {
  try {
    const res = await fetch("/api/status")
    const data = await res.json()
    $status.textContent = data.ok ? "Connected to qmd." : "qmd not reachable — check the server log."
  } catch {
    $status.textContent = "qmd not reachable."
  }
})()
