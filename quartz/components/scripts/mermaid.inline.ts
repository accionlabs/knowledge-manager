import { registerEscapeHandler, removeAllChildren } from "./util"

interface Position {
  x: number
  y: number
}

class DiagramPanZoom {
  private isDragging = false
  private startPan: Position = { x: 0, y: 0 }
  private currentPan: Position = { x: 0, y: 0 }
  private scale = 1
  private readonly MIN_SCALE = 0.5
  private readonly MAX_SCALE = 3

  cleanups: (() => void)[] = []

  constructor(
    private container: HTMLElement,
    private content: HTMLElement,
  ) {
    this.setupEventListeners()
    this.setupNavigationControls()
    this.resetTransform()
  }

  private setupEventListeners() {
    // Mouse drag events
    const mouseDownHandler = this.onMouseDown.bind(this)
    const mouseMoveHandler = this.onMouseMove.bind(this)
    const mouseUpHandler = this.onMouseUp.bind(this)

    // Touch drag events
    const touchStartHandler = this.onTouchStart.bind(this)
    const touchMoveHandler = this.onTouchMove.bind(this)
    const touchEndHandler = this.onTouchEnd.bind(this)

    const resizeHandler = this.resetTransform.bind(this)

    this.container.addEventListener("mousedown", mouseDownHandler)
    document.addEventListener("mousemove", mouseMoveHandler)
    document.addEventListener("mouseup", mouseUpHandler)

    this.container.addEventListener("touchstart", touchStartHandler, { passive: false })
    document.addEventListener("touchmove", touchMoveHandler, { passive: false })
    document.addEventListener("touchend", touchEndHandler)

    window.addEventListener("resize", resizeHandler)

    this.cleanups.push(
      () => this.container.removeEventListener("mousedown", mouseDownHandler),
      () => document.removeEventListener("mousemove", mouseMoveHandler),
      () => document.removeEventListener("mouseup", mouseUpHandler),
      () => this.container.removeEventListener("touchstart", touchStartHandler),
      () => document.removeEventListener("touchmove", touchMoveHandler),
      () => document.removeEventListener("touchend", touchEndHandler),
      () => window.removeEventListener("resize", resizeHandler),
    )
  }

  cleanup() {
    for (const cleanup of this.cleanups) {
      cleanup()
    }
  }

  private setupNavigationControls() {
    const controls = document.createElement("div")
    controls.className = "mermaid-controls"

    // Zoom controls
    const zoomIn = this.createButton("+", () => this.zoom(0.1))
    const zoomOut = this.createButton("-", () => this.zoom(-0.1))
    const resetBtn = this.createButton("Reset", () => this.resetTransform())

    controls.appendChild(zoomOut)
    controls.appendChild(resetBtn)
    controls.appendChild(zoomIn)

    this.container.appendChild(controls)
  }

  private createButton(text: string, onClick: () => void): HTMLButtonElement {
    const button = document.createElement("button")
    button.textContent = text
    button.className = "mermaid-control-button"
    button.addEventListener("click", onClick)
    window.addCleanup(() => button.removeEventListener("click", onClick))
    return button
  }

  private onMouseDown(e: MouseEvent) {
    if (e.button !== 0) return // Only handle left click
    this.isDragging = true
    this.startPan = { x: e.clientX - this.currentPan.x, y: e.clientY - this.currentPan.y }
    this.container.style.cursor = "grabbing"
  }

  private onMouseMove(e: MouseEvent) {
    if (!this.isDragging) return
    e.preventDefault()

    this.currentPan = {
      x: e.clientX - this.startPan.x,
      y: e.clientY - this.startPan.y,
    }

    this.updateTransform()
  }

  private onMouseUp() {
    this.isDragging = false
    this.container.style.cursor = "grab"
  }

  private onTouchStart(e: TouchEvent) {
    if (e.touches.length !== 1) return
    this.isDragging = true
    const touch = e.touches[0]
    this.startPan = { x: touch.clientX - this.currentPan.x, y: touch.clientY - this.currentPan.y }
  }

  private onTouchMove(e: TouchEvent) {
    if (!this.isDragging || e.touches.length !== 1) return
    e.preventDefault() // Prevent scrolling

    const touch = e.touches[0]
    this.currentPan = {
      x: touch.clientX - this.startPan.x,
      y: touch.clientY - this.startPan.y,
    }

    this.updateTransform()
  }

  private onTouchEnd() {
    this.isDragging = false
  }

  private zoom(delta: number) {
    const newScale = Math.min(Math.max(this.scale + delta, this.MIN_SCALE), this.MAX_SCALE)

    // Zoom around center
    const rect = this.content.getBoundingClientRect()
    const centerX = rect.width / 2
    const centerY = rect.height / 2

    const scaleDiff = newScale - this.scale
    this.currentPan.x -= centerX * scaleDiff
    this.currentPan.y -= centerY * scaleDiff

    this.scale = newScale
    this.updateTransform()
  }

  private updateTransform() {
    this.content.style.transform = `translate(${this.currentPan.x}px, ${this.currentPan.y}px) scale(${this.scale})`
  }

  private resetTransform() {
    const svg = this.content.querySelector("svg")!
    const rect = svg.getBoundingClientRect()
    const width = rect.width / this.scale
    const height = rect.height / this.scale

    this.scale = 1
    this.currentPan = {
      x: (this.container.clientWidth - width) / 2,
      y: (this.container.clientHeight - height) / 2,
    }
    this.updateTransform()
  }
}

const cssVars = [
  "--secondary",
  "--tertiary",
  "--gray",
  "--light",
  "--lightgray",
  "--highlight",
  "--dark",
  "--darkgray",
  "--codeFont",
] as const

let mermaidLoaded: Promise<any> | undefined
function loadMermaidScript(): Promise<any> {
  if (mermaidLoaded) return mermaidLoaded
  mermaidLoaded = new Promise((resolve, reject) => {
    const existing = (window as any).mermaid
    if (existing) return resolve(existing)
    const script = document.createElement("script")
    script.src = "https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"
    script.onload = () => resolve((window as any).mermaid)
    script.onerror = reject
    document.head.appendChild(script)
  })
  return mermaidLoaded
}

document.addEventListener("nav", async () => {
  const center = document.querySelector(".center") as HTMLElement
  const codeBlocks = center.querySelectorAll(
    "pre > code.mermaid",
  ) as NodeListOf<HTMLElement>
  if (codeBlocks.length === 0) return

  // Unwrap each <pre><code class="mermaid">...</code></pre> into a plain
  // <div class="mermaid">...</div>. This matches how Hugo handles mermaid
  // and sidesteps all the <pre> styling (overflow-x, grid display, padding)
  // that prevents proper scaling on screen and reliable print output.
  const nodes: HTMLElement[] = []
  codeBlocks.forEach((code, i) => {
    const pre = code.parentElement as HTMLPreElement
    const div = document.createElement("div")
    div.className = "mermaid"
    div.id = `mermaid-${i}`
    div.textContent = code.textContent || ""
    pre.parentNode?.replaceChild(div, pre)
    nodes.push(div)
  })

  const mermaid = await loadMermaidScript()

  const textMapping: WeakMap<HTMLElement, string> = new WeakMap()
  for (const node of nodes) {
    textMapping.set(node, node.textContent || "")
  }

  async function renderMermaid() {
    // de-init any previous renders so theme changes can re-render cleanly
    for (const node of nodes) {
      node.removeAttribute("data-processed")
      const oldText = textMapping.get(node)
      if (oldText) {
        node.textContent = oldText
      }
    }

    const darkMode = document.documentElement.getAttribute("saved-theme") === "dark"
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "loose",
      theme: darkMode ? "dark" : "default",
      flowchart: { useMaxWidth: true, htmlLabels: true },
    })

    try {
      await mermaid.run({ querySelector: ".mermaid" })
    } catch (err) {
      console.warn("Mermaid failed to render a diagram:", err)
    }
  }

  await renderMermaid()
  document.addEventListener("themechange", renderMermaid)
  window.addCleanup(() => document.removeEventListener("themechange", renderMermaid))
})
