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
const script = JSON.parse("[" + block.slice(block.indexOf("[") + 1, block.lastIndexOf("]")).replace(/"\s*\+\s*"/g, "") + "]")[2]

const dir = mkdtempSync(join(tmpdir(), "paste-bound-"))
function run(body) {
  writeFileSync(join(dir, "wl-paste"), "#!/bin/bash\n" + body + "\n")
  chmodSync(join(dir, "wl-paste"), 0o755)
  const t = Date.now()
  const r = spawnSync("bash", ["-c", script], { env: { ...process.env, PATH: dir + ":" + process.env.PATH }, encoding: "utf8" })
  return { out: r.stdout, ms: Date.now() - t }
}
try {
  assert.equal(run("printf 'héllo\\nworld'").out, "ok:héllo\nworld")
  assert.equal(run("head -c 65536 /dev/zero | tr '\\0' a").out.length, 3 + 65536, "64 KiB exactly is allowed")
  assert.equal(run("head -c 65537 /dev/zero | tr '\\0' a").out, "", "one byte over the cap")
  assert.equal(run("yes").out, "", "endless stream")
  assert.equal(run("exit 1").out, "", "empty clipboard")
  const slow = run("printf partial; exec sleep 30")
  assert.equal(slow.out, "", "stalled owner")
  assert.ok(slow.ms < 4000, `deadline overran: ${slow.ms} ms`)
} finally { rmSync(dir, { recursive: true }) }

// finishPaste: replaces the selection, flattens newlines, drops stale results
const at = qml.indexOf("  function finishPaste(")
const body = qml.slice(qml.indexOf("{", at), qml.indexOf("\n  }\n", at) + 4)
const finish = new Function("root", "output", body)
const field = (text, s, e, focus = true) => ({
  text, selectionStart: s, selectionEnd: e, cursorPosition: e, activeFocus: focus,
  get selectedText() { return this.text.slice(this.selectionStart, this.selectionEnd) },
  remove(a, b) { this.text = this.text.slice(0, a) + this.text.slice(b); this.cursorPosition = a; this.selectionEnd = this.selectionStart = a },
  insert(p, t) { this.text = this.text.slice(0, p) + t + this.text.slice(p) },
})
let f = field("fire fox", 0, 4); finish({ pasteTarget: f, opened: true }, "ok:water\r\n"); assert.equal(f.text, "water  fox")
f = field("ab", 2, 2, false); finish({ pasteTarget: f, opened: true }, "ok:x"); assert.equal(f.text, "ab", "pasted into an unfocused field")
f = field("ab", 2, 2); finish({ pasteTarget: f, opened: false }, "ok:x"); assert.equal(f.text, "ab", "pasted after close")
f = field("ab", 2, 2); finish({ pasteTarget: f, opened: true }, ""); assert.equal(f.text, "ab", "pasted a rejected read")
console.log("ok paste-bound")
