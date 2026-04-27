// qmd-search — tiny HTTP wrapper around the `qmd` CLI.
// - GET /            → serves the static UI (index.html, app.js, styles.css).
// - GET /api/search  → shells out to `qmd query <q> --json -n <limit>` and
//                      returns the parsed JSON.
// - GET /api/status  → returns { ok, collections } so the UI can show errors.
//
// No dependencies — Node 18+ ships with everything we need.
//
// Run with:  node server.mjs [--port 9090] [--qmd /opt/homebrew/bin/qmd]

import http from "node:http"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { spawn } from "node:child_process"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// --- args ---------------------------------------------------------------
const args = process.argv.slice(2)
function arg(name, fallback) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : fallback
}
const PORT = Number(arg("--port", "9090"))
const QMD_BIN = arg("--qmd", "qmd")

// --- helpers ------------------------------------------------------------
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
}

function serveStatic(req, res) {
  const requested = req.url.split("?")[0]
  let rel = requested === "/" ? "/index.html" : requested
  // prevent path traversal
  if (rel.includes("..")) return notFound(res)
  const fp = path.join(__dirname, rel)
  if (!fp.startsWith(__dirname)) return notFound(res)
  fs.readFile(fp, (err, buf) => {
    if (err) return notFound(res)
    res.writeHead(200, {
      "content-type": MIME[path.extname(fp)] ?? "application/octet-stream",
      "cache-control": "no-store",
    })
    res.end(buf)
  })
}

function notFound(res) {
  res.writeHead(404, { "content-type": "text/plain" })
  res.end("Not found")
}

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
  })
  res.end(JSON.stringify(body))
}

function runQmd(args, { timeoutMs = 60000 } = {}) {
  return new Promise((resolve) => {
    const child = spawn(QMD_BIN, args, { stdio: ["ignore", "pipe", "pipe"] })
    let stdout = "", stderr = ""
    let timedOut = false
    const timer = setTimeout(() => {
      timedOut = true
      child.kill("SIGTERM")
      setTimeout(() => child.kill("SIGKILL"), 1000)
    }, timeoutMs)
    child.stdout.on("data", (b) => (stdout += b))
    child.stderr.on("data", (b) => (stderr += b))
    child.on("error", (err) => {
      clearTimeout(timer)
      resolve({ ok: false, error: err.message, stdout, stderr })
    })
    child.on("close", (code) => {
      clearTimeout(timer)
      resolve({ ok: !timedOut && code === 0, code, stdout, stderr, timedOut })
    })
  })
}

// qmd's --json output is preceded by progress lines on stdout. Find the JSON
// payload by scanning for the first '[' that begins a top-level array.
function extractJsonArray(stdout) {
  const start = stdout.indexOf("\n[\n")
  if (start === -1) {
    // Some versions emit the array contiguously
    const alt = stdout.indexOf("[")
    if (alt === -1) return null
    return stdout.slice(alt)
  }
  return stdout.slice(start + 1)
}

// --- request handler ----------------------------------------------------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost")

  if (url.pathname === "/api/status") {
    const r = await runQmd(["status"], { timeoutMs: 10000 })
    return json(res, 200, { ok: r.ok, raw: r.stdout, error: r.stderr || null })
  }

  if (url.pathname === "/api/search") {
    const q = url.searchParams.get("q")?.trim() ?? ""
    const limit = Math.min(50, Math.max(1, Number(url.searchParams.get("n") || "20")))
    const mode = url.searchParams.get("mode") || "query" // query | search | vsearch
    if (!q) return json(res, 400, { error: "missing q" })

    const validModes = new Set(["query", "search", "vsearch"])
    if (!validModes.has(mode)) return json(res, 400, { error: "invalid mode" })

    const r = await runQmd([mode, q, "--json", "-n", String(limit)], {
      timeoutMs: 90000,
    })
    if (!r.ok) {
      return json(res, 500, {
        error: r.timedOut ? "qmd query timed out" : "qmd failed",
        code: r.code,
        stderr: r.stderr,
      })
    }
    const payload = extractJsonArray(r.stdout)
    if (!payload) return json(res, 500, { error: "no JSON in qmd output", stdout: r.stdout })
    try {
      const results = JSON.parse(payload)
      return json(res, 200, { results })
    } catch (e) {
      return json(res, 500, { error: "could not parse qmd JSON", raw: payload.slice(0, 400) })
    }
  }

  serveStatic(req, res)
})

server.listen(PORT, () => {
  console.log(`qmd-search listening on http://localhost:${PORT}`)
  console.log(`qmd binary: ${QMD_BIN}`)
})
