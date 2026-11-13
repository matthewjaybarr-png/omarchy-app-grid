// node tests/paste-bound.mjs
// Runs the real pasteProc command from LauncherView.qml against a fake
// wl-paste, and the real finishPaste body against a stub field.
import { readFileSync, mkdtempSync, writeFileSync, chmodSync, rmSync } from "node:fs"
import { spawnSync } from "node:child_process"
import { tmpdir } from "node:os"
import { join } from "node:path"
import assert from "node:assert/strict"

const qml = readFileSync(new URL("../LauncherView.qml", import.meta.url), "utf8")
const block = qml.slice(qml.indexOf("id: pasteProc"), qml.indexOf("stdout:", qml.indexOf("id: pasteProc")))
const script = JSON.parse("[" + block.slice(block.indexOf("[") + 1, block.indexOf(', "paste"')).replace(/"\s*\+\s*"/g, "") + "]")[2]

const dir = mkdtempSync(join(tmpdir(), "paste-bound-"))
function run(body) {
  writeFileSync(join(dir, "wl-paste"), "#!/bin/bash\n" + body + "\n")
  chmodSync(join(dir, "wl-paste"), 0o755)
  const t = Date.now()
  const r = spawnSync("bash", ["-c", script, "paste", "7"], { env: { ...process.env, PATH: dir + ":" + process.env.PATH }, encoding: "utf8" })
  return { out: r.stdout, ms: Date.now() - t }
}
try {
  assert.equal(run("printf 'héllo\\nworld'").out, "7 ok:héllo\nworld")
  assert.equal(run("head -c 65536 /dev/zero | tr '\\0' a").out.length, 5 + 65536, "64 KiB exactly is allowed")
  assert.equal(run("head -c 65537 /dev/zero | tr '\\0' a").out, "", "one byte over the cap")
  assert.equal(run("yes").out, "", "endless stream")
  assert.equal(run("exit 1").out, "", "empty clipboard")
  const slow = run("printf partial; exec sleep 30")
  assert.equal(slow.out, "", "stalled owner")
  assert.ok(slow.ms < 4000, `deadline overran: ${slow.ms} ms`)
} finally { rmSync(dir, { recursive: true }) }

// finishPaste / pasteInto / cancelPaste: real bodies against a stub root and field
function fn(name) {
  const at = qml.indexOf(`  function ${name}(`)
  let depth = 0
  for (let i = qml.indexOf("{", at); ; i++) {
    if (qml[i] === "{") depth++
    else if (qml[i] === "}" && --depth === 0) return qml.slice(at + 2, i + 1)
  }
}
const field = (text, s, e, focus = true) => ({
  text, selectionStart: s, selectionEnd: e, cursorPosition: e, activeFocus: focus,
  get selectedText() { return this.text.slice(this.selectionStart, this.selectionEnd) },
  remove(a, b) { this.text = this.text.slice(0, a) + this.text.slice(b); this.cursorPosition = a; this.selectionEnd = this.selectionStart = a },
  insert(p, t) { this.text = this.text.slice(0, p) + t + this.text.slice(p) },
})
function setup() {
  const pasteProc = { running: false }
  const root = { pasteTarget: null, pasteReq: 0, opened: true }
  for (const n of ["pasteInto", "cancelPaste", "finishPaste"])
    root[n] = new Function("root", "pasteProc", `return ${fn(n)}`)(root, pasteProc)
  return { root, pasteProc }
}
{ // replaces the selection, flattens newlines
  const { root, pasteProc } = setup(), f = field("fire fox", 0, 4)
  root.pasteInto(f); assert.ok(pasteProc.running)
  root.finishPaste(`${root.pasteReq} ok:water\r\n`); assert.equal(f.text, "water  fox")
}
{ // rejected read, unfocused field, closed grid
  for (const [why, out, focus, opened] of [["rejected read", "", true, true], ["unfocused field", "ok", false, true], ["after close", "ok", true, false]]) {
    const { root } = setup(), f = field("ab", 2, 2, focus)
    root.pasteInto(f); root.opened = opened
    root.finishPaste(out && `${root.pasteReq} ok:x`); assert.equal(f.text, "ab", `pasted: ${why}`)
  }
}
{ // a second paste while one is in flight does not retarget it
  const { root } = setup(), a = field("a", 1, 1), b = field("b", 1, 1)
  root.pasteInto(a); const req = root.pasteReq; root.pasteInto(b)
  root.finishPaste(`${req} ok:x`); assert.deepEqual([a.text, b.text], ["ax", "b"])
}
{ // close + reopen, or blur + refocus, while in flight: the old result is dropped
  for (const cancel of [r => r.cancelPaste(null), (r, f) => r.cancelPaste(f)]) {
    const { root, pasteProc } = setup(), f = field("ab", 2, 2)
    root.pasteInto(f); const req = root.pasteReq
    cancel(root, f); assert.equal(pasteProc.running, false, "read not stopped")
    root.finishPaste(`${req} ok:x`); assert.equal(f.text, "ab", "stale result accepted")
    root.pasteInto(f); root.finishPaste(`${req} ok:x`); assert.equal(f.text, "ab", "old id accepted by a new read")
    root.finishPaste(`${root.pasteReq} ok:y`); assert.equal(f.text, "aby")
  }
  const { root, pasteProc } = setup(), a = field("a", 1, 1)
  root.pasteInto(a); root.cancelPaste(field("other", 0, 0))
  assert.ok(pasteProc.running, "blurring another field cancelled the read")
}

// PNG scan: the real command against fake icon dirs. A complete scan exits 0;
// hitting the cap or an unreadable dir exits non-zero, which keeps the old index.
{
  const a = qml.indexOf("function pngScanCommand"), b = qml.indexOf("].join", a)
  const scanCmd = [...qml.slice(a, b).matchAll(/^\s*'(.*)',?$/gm)].map(m => m[1].replace(/\\\\/g, "\\")).join(" ")
  assert.match(qml, /command: \["timeout", "-k", "1", "10", "bash", "-c", root\.pngScanCommand\(\)\]/)
  assert.match(qml, /onExited: function\(code\) \{ if \(code === 0\) root\.pngIndex/)
  const home = mkdtempSync(join(tmpdir(), "png-scan-")), apps = join(home, ".icons/hicolor/48x48/apps")
  const scanRun = (cmd, env = {}) => spawnSync("bash", ["-c", cmd], { env: { ...process.env, HOME: home, XDG_DATA_DIRS: join(home, "none"), ...env }, encoding: "utf8" })
  try {
    spawnSync("mkdir", ["-p", apps])
    for (const n of ["a", "b", "c"]) writeFileSync(join(apps, n + ".png"), "")
    let r = scanRun(scanCmd); assert.equal(r.status, 0); assert.equal(r.stdout.trim().split("\n").filter(l => l.startsWith(home)).length, 3)
    r = scanRun(scanCmd.replace("head -n 50000", "head -n 1")); assert.notEqual(r.status, 0, "scan cut off by the cap passed as complete")
    chmodSync(apps, 0); r = scanRun(scanCmd); chmodSync(apps, 0o755)
    if (process.getuid() !== 0) assert.notEqual(r.status, 0, "find error passed as complete")
  } finally { rmSync(home, { recursive: true }) }
}

// wallpaperProbe: deadline, watchdog, and stream/exit in either order
{
  const at = qml.indexOf("id: wallpaperProbe"), probe = qml.slice(at, qml.indexOf("id: wallpaperWatchdog", at))
  assert.match(probe, /command: \["timeout", "-k", "1", "2", "readlink"/)
  assert.match(probe, /onExited: function\(exitCode\) \{ wallpaperWatchdog\.stop\(\)/)
  const settleBody = probe.slice(probe.indexOf("function settle()"), probe.indexOf("\n    }\n", probe.indexOf("function settle()")) + 6)
  const make = () => { const root = { wallpaperPath: "old" }; const p = { found: null, code: null, root }; p.settle = new Function("p", "root", `with (p) { return ${settleBody} }`)(p, root); return p }  // QML scope: bare names hit the Process
  for (const [found, code, want] of [["/w.jpg", 0, "/w.jpg"], ["", 0, "old"], ["/w.jpg", 124, "old"], ["x".repeat(5000), 0, "old"]]) {
    for (const order of [0, 1]) {
      const p = make()
      if (order) { p.code = code; p.settle(); assert.equal(p.root.wallpaperPath, "old", "applied before the stream ended"); p.found = found; p.settle() }
      else { p.found = found; p.settle(); assert.equal(p.root.wallpaperPath, "old", "applied before exit"); p.code = code; p.settle() }
      assert.equal(p.root.wallpaperPath, want, `found=${found.slice(0, 9)} code=${code}`)
    }
  }
}
console.log("ok paste-bound")
