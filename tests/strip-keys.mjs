// node tests/strip-keys.mjs
// Runs the real strip* function bodies from LauncherView.qml against a stub
// root and a fake Hyprland.
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const qml = readFileSync(new URL("../LauncherView.qml", import.meta.url), "utf8")

function fn(name) {
  const at = qml.indexOf(`  function ${name}(`)
  assert.ok(at >= 0, `${name} not found`)
  let depth = 0
  for (let i = qml.indexOf("{", at); i < qml.length; i++) {
    if (qml[i] === "{") depth++
    else if (qml[i] === "}" && --depth === 0) return qml.slice(at + 2, i + 1)
  }
  throw new Error(`${name}: unbalanced braces`)
}

const win = (address, ws) => ({ address, title: "t" + address, ws, get workspace() { return { id: this.ws } } })
function setup(windows, expanded = true, ids = [1, 2, 3]) {
  const Hyprland = { toplevels: { values: windows }, focusedWorkspace: { id: 2 } }
  const log = []
  const root = {
    zone: "grid", stripWs: 0, stripWindow: "", stripMove: "", stripHint: "", stripExpanded: expanded,
    dragActive: false, menuEntry: null, openFolderId: "",
    workspaceIds: () => ids,
    workspaceById: id => id,
    workspaceWindows: id => windows.filter(w => w.ws === id),
    windowTitle: t => t.title, workspaceHint: id => "ws" + id,
    moveWindow: (t, id) => log.push(["move", t.address, id]),
    closeWindow: t => log.push(["close", t.address]),
    focusWindow: t => log.push(["focus", t.address]),
    focusWorkspace: id => log.push(["ws", id]),
  }
  for (const n of ["stripWindows", "stripToplevel", "stripValidate", "stripSelect", "stripEnter",
                   "stripLeave", "stripStep", "stripCycle", "stripShift", "stripClose", "stripActivate"])
    root[n] = new Function("root", "Hyprland", `return ${fn(n)}`)(root, Hyprland)
  return { root, log, Hyprland }
}
const sel = r => [r.stripWs, r.stripWindow]

{ // enter on the focused workspace; Left/Right clamp
  const { root } = setup([])
  assert.ok(root.stripEnter()); assert.deepEqual(sel(root), [2, ""])
  root.stripStep(5); assert.equal(root.stripWs, 3)
  root.stripStep(-9); assert.equal(root.stripWs, 1)
  root.menuEntry = {}; root.zone = "grid"
  assert.equal(root.stripEnter(), false, "entered with a menu open")
}
{ // Tab wraps card -> windows -> card; collapsed it steps workspaces instead
  const { root } = setup([win("a", 2), win("b", 2)])
  root.stripEnter()
  root.stripCycle(1); assert.deepEqual(sel(root), [2, "a"])
  root.stripCycle(1); root.stripCycle(1); assert.deepEqual(sel(root), [2, ""])
  root.stripCycle(-1); assert.deepEqual(sel(root), [2, "b"])
  root.stripExpanded = false; root.stripCycle(1); assert.deepEqual(sel(root), [3, ""])
}
{ // Shift+Right moves, the selection follows, a second press still works
  const { root, log } = setup([win("a", 2)])
  root.stripEnter(); root.stripCycle(1)
  root.stripShift(1); root.stripShift(-1)
  assert.deepEqual(log, [["move", "a", 3], ["move", "a", 2]])
  root.stripShift(-1); root.stripShift(-1); root.stripShift(-1)
  assert.deepEqual(sel(root), [1, "a"], "moved past the first id")
  assert.equal(root.stripWindow, "a", "pending move lost the selection")
  const card = setup([]).root; card.stripEnter(); card.stripShift(1)
  assert.equal(card.stripWs, 2, "Shift on a card moved something")
}
{ // Delete selects the neighbour before closing; the last one picks the previous
  const { root, log } = setup([win("a", 2), win("b", 2), win("c", 2)])
  root.stripEnter(); root.stripCycle(1)
  root.stripClose(); assert.deepEqual(sel(root), [2, "b"]); assert.deepEqual(log, [["close", "a"]])
  root.stripSelect(2, "c"); root.stripClose(); assert.equal(root.stripWindow, "b")
  root.stripSelect(2, "b"); root.stripClose(); root.stripSelect(2, "b")
}
{ // gone address -> card; gone workspace -> focused one; Enter; drag blocks keys
  const { root, log, Hyprland } = setup([win("a", 2)])
  root.stripEnter(); root.stripCycle(1)
  Hyprland.toplevels.values.length = 0
  root.stripActivate(); assert.deepEqual(log, [["ws", 2]]); assert.equal(root.stripWindow, "")
  root.stripWs = 9; root.stripStep(0); assert.equal(root.stripWs, 2)
  root.dragActive = true; root.stripStep(1); assert.equal(root.stripWs, 2)
  root.stripActivate(); assert.equal(log.length, 1)
}
{ // moved from outside: selection follows the window, or drops if it left the strip
  const w = win("a", 2), { root, log } = setup([w])
  root.stripEnter(); root.stripCycle(1)
  w.ws = 3; root.stripClose(); assert.deepEqual(log, [["close", "a"]])
  assert.equal(root.stripWs, 3, "stayed on the old workspace")
  root.stripSelect(3, "a"); w.ws = 7; root.stripValidate()
  assert.equal(root.stripWindow, "", "kept a window that left the strip")
  // a pending keyboard move survives validation, and clears once it lands
  const m = win("b", 1), p = setup([m]).root
  p.stripEnter(); p.stripWs = 1; p.stripSelect(1, "b"); p.stripShift(1)
  p.stripValidate(); assert.deepEqual(sel(p), [2, "b"]); m.ws = 2; p.stripValidate()
  assert.equal(p.stripMove, "")
}
{ // move requested, strip left before it was seen landing, then reselected
  const w = win("a", 2), { root, log } = setup([w])
  root.stripEnter(); root.stripCycle(1); root.stripShift(1)
  root.stripLeave(); w.ws = 3
  root.stripEnter(); root.stripStep(1); root.stripCycle(1)
  assert.deepEqual(sel(root), [3, "a"])
  w.ws = 7; root.stripClose()
  assert.equal(log.length, 1, "closed a window that left the strip on stale protection")
}
{ // opening a menu or folder leaves the strip (real handler bodies)
  const run = name => {
    const at = qml.indexOf(`  ${name}:`), end = qml.indexOf("\n\n", at)
    return new Function("root", "searchInput", qml.slice(at, end).replace(`${name}:`, ""))
  }
  for (const [name, set] of [["onMenuEntryChanged", r => r.menuEntry = {}], ["onOpenFolderIdChanged", r => r.openFolderId = "f"]]) {
    const { root } = setup([]); root.stripEnter()
    set(root); run(name)(root, { forceActiveFocus() {} })
    assert.equal(root.zone, "grid", `${name} left the strip open`)
  }
}
console.log("ok strip-keys")
