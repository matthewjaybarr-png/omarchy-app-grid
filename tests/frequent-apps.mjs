// node tests/frequent-apps.mjs
// Runs the real usage functions from LauncherView.qml.
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const qml = readFileSync(new URL("../LauncherView.qml", import.meta.url), "utf8")
function block(start) {
  const at = qml.indexOf(start)
  assert.ok(at >= 0, `${start} not found`)
  let depth = 0
  for (let i = qml.indexOf("{", at); i < qml.length; i++) {
    if (qml[i] === "{") depth++
    else if (qml[i] === "}" && --depth === 0) return qml.slice(qml.indexOf("{", at) + 1, i)
  }
  throw new Error(`${start}: unbalanced braces`)
}
const root = {}
const fn = (name, args) => (root[name] = (...a) => new Function("root", ...args, block(`  function ${name}(`))(root, ...a))
fn("decayedScore", ["rec", "now"]); fn("bumpUsage", ["usage", "id", "now"])
fn("frequentIds", ["usage", "now", "limit", "skip"]); fn("boostRows", ["rows", "usage", "now"])

const DAY = 864e5, now = 100 * DAY
assert.equal(root.decayedScore([4, now - 7 * DAY], now), 2)
assert.equal(root.decayedScore("a", now), 0)
assert.equal(root.decayedScore(undefined, now), 0)

assert.deepEqual(root.bumpUsage({}, "a", now).a, [1, now])
const before = { a: [2, now - 7 * DAY] }
assert.equal(root.bumpUsage(before, "a", now).a[0], 2)
assert.deepEqual(before, { a: [2, now - 7 * DAY] }, "input unchanged")
let u = {}
for (let i = 0; i <= 40; i++) u = root.bumpUsage(u, String(i), now + i)
assert.equal(Object.keys(u).length, 40)
assert.ok(!("0" in u), "oldest dropped")
assert.ok(!("x" in root.bumpUsage({ x: "bad" }, "a", now)))
assert.deepEqual(Object.keys(root.bumpUsage([], "a", now)), ["a"])

const usage = { a: [1, now], b: [3, now], c: [2, now] }
assert.deepEqual(root.frequentIds(usage, now, 2, () => false), ["b", "c"])
assert.deepEqual(root.frequentIds(usage, now, 8, id => id === "b"), ["c", "a"])
assert.deepEqual(root.frequentIds([], now, 8, () => false), [])
assert.deepEqual(root.frequentIds({ x: "a" }, now, 8, () => false), [])

const rows = [{ entry: { id: "files" }, score: 9995 }, { entry: { id: "firefox" }, score: 9993 },
  { entry: { id: "signal" }, score: 7990 }]
assert.deepEqual(root.boostRows(rows, { firefox: [5, now], signal: [50, now] }, now).map(r => r.entry.id),
  ["firefox", "files", "signal"], "usage reorders within a band, never across")
// A name match mid-word (8000 - 10*pos - len) beats a heavily used id-only match (7600 - ...).
assert.deepEqual(root.boostRows([{ entry: { id: "x.signal" }, score: 7560 }, { entry: { id: "files" }, score: 7950 }],
  { "x.signal": [50, now] }, now).map(r => r.entry.id), ["files", "x.signal"])
assert.deepEqual(root.boostRows(rows, undefined, now).map(r => r.entry.id), ["files", "firefox", "signal"])

assert.ok((block("  function launchEntry(").match(/root\.recordUse\(entry\.id\)/g) || []).length >= 2)
assert.match(block("  function launchOnWorkspace("), /root\.recordUse\(/)
assert.match(block("  function refreshApps("), /root\.boostRows\(/)
assert.match(qml, /property var usage: \(\{\}\)/)
assert.match(qml, /property bool showFrequent: true/)

// Gear menu toggle, on unless explicitly off.
const settings = block("    if (entry.isSettings) {")
const menu = prefs => new Function("root", "prefs", settings)({ previewMode: () => "live" }, prefs)
assert.deepEqual(menu({ showFrequent: false }).at(-1), { label: "   Show frequent apps", action: "frequent" })
assert.equal(menu({}).at(-1).label, "✓  Show frequent apps")
assert.match(block("  function runMenuAction("), /case "frequent":\s*prefs\.showFrequent = prefs\.showFrequent === false/)

// The row takes a grid row; keys walk grid -> row -> strip and back.
assert.match(qml, /readonly property int rows:[^\n]*\n[^\n]*root\.frequentShown \? root\.cellHeight : 0/)
const keys = block("          Keys.onPressed: function(event) {")
assert.match(keys, /root\.zone === "frequent"/)
assert.match(keys, /root\.frequentEnter\(\) \|\| root\.stripEnter\(\)/)
assert.match(keys, /!root\.dragActive && !root\.frequentEnter\(\)/)
assert.match(qml, /onFrequentShownChanged: if \(!root\.frequentShown && root\.zone === "frequent"\) root\.zone = "grid"/)
assert.match(block("  onOpenFolderIdChanged: {"), /root\.zone === "frequent"\) root\.zone = "grid"/)
assert.match(qml, /onPageCountChanged: if \(root\.page >= root\.pageCount\) root\.page = root\.pageCount - 1/)

console.log("ok frequent-apps")
