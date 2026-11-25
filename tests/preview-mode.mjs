// node tests/preview-mode.mjs
// Runs the real previewMode() and the settings menu items from LauncherView.qml.
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

const previewMode = (prefs) => new Function("prefs", block("  function previewMode(")).call(null, prefs)
assert.equal(previewMode({}), "live", "missing key reads as live")
assert.equal(previewMode({ previews: "foo" }), "live")
assert.equal(previewMode({ previews: true }), "live")
assert.equal(previewMode({ previews: "still" }), "still")
assert.equal(previewMode({ previews: "off" }), "off")

// The pref exists on the saved JsonAdapter with a live default.
assert.match(qml, /property string previews: "live"/)

// The settings branch of menuItems, with the real previewMode behind root.
const settings = block("    if (entry.isSettings) {")
function settingsItems(prefs) {
  const root = { previewMode: () => previewMode(prefs) }
  return new Function("root", "prefs", settings)(root, prefs)
}
const items = settingsItems({ previews: "still" })
assert.deepEqual(items.map(i => i.label), [
  "✓  Switch to open apps", "   Always open new windows",
  "   Live previews", "✓  Still previews", "   No previews (icons only)", "✓  Show frequent apps"])
assert.deepEqual(items.slice(2, 5).map(i => i.action), ["previews-live", "previews-still", "previews-off"])
assert.equal(settingsItems({}).filter(i => i.label.startsWith("✓")).length, 3, "default: one tick per group")

// The menu action stores the mode named after "previews-".
const run = block("  function runMenuAction(")
assert.match(run, /case "previews-live":\s*case "previews-still":\s*case "previews-off":\s*prefs\.previews = action\.slice\(9\)/)
assert.equal("previews-still".slice(9), "still")

// The card preview follows the mode; Off drops the capture entirely.
const view = block("                  ScreencopyView {")
assert.match(view, /live: root\.previewMode\(\) === "live"/)
assert.match(view, /captureSource: root\.opened && root\.stripExpanded && root\.previewMode\(\) !== "off"/)

console.log("ok preview-mode")
