// node tests/drag-cancel.mjs
// Runs the real press/move/release/click handler bodies from LauncherView.qml
// against a stub root: Escape mid-drag must end that press's drag for good,
// and a fresh press must be able to drag again.
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const qml = readFileSync(new URL("../LauncherView.qml", import.meta.url), "utf8")

// The MouseArea that declares `id: <id>`, and one of its handlers as source.
function handler(id, name) {
  const block = qml.slice(qml.indexOf(`id: ${id}\n`))
  const at = block.indexOf(`${name}:`)
  assert.ok(at >= 0, `${id}.${name} not found`)
  const rest = block.slice(at + name.length + 1).trimStart()
  if (!rest.startsWith("function")) return `function(mouse) { ${rest.split("\n")[0]} }`
  let depth = 0
  for (let i = rest.indexOf("{"); i < rest.length; i++) {
    if (rest[i] === "{") depth++
    else if (rest[i] === "}" && --depth === 0) return rest.slice(0, i + 1)
  }
  throw new Error(`${id}.${name}: unbalanced braces`)
}

function check(id, item) {
  const root = {
    dragActive: false, dragThreshold: 10, query: "", begun: 0, ended: 0, actions: [],
    beginDrag() { this.dragActive = true; this.begun++ },
    beginWindowDrag() { this.dragActive = true; this.begun++ },
    updateDrag() {}, endDrag() { this.ended++ }, cancelDrag() { this.dragActive = false },
    wantsFresh: () => false,
  }
  for (const a of ["focusWindow", "closeWindow", "launchEntry", "launch", "openMenu"])
    root[a] = () => root.actions.push(a)
  const area = { pressed: false }
  const target = { mapToItem: (_, x, y) => ({ x, y }) }
  const Qt = { LeftButton: 1, RightButton: 2, MiddleButton: 4 }
  const names = ["root", "Qt", id, item, "favIcon", "art"]
  const make = name => new Function(...names, `return ${handler(id, name)}`)(root, Qt, area, target, {}, {})
  const [press, move, release, click] = ["onPressed", "onPositionChanged", "onReleased", "onClicked"].map(make)
  const left = (x = 0) => ({ button: Qt.LeftButton, x, y: 0 })

  area.pressed = true; press(left())
  move(left(5)); assert.equal(root.begun, 0, `${id}: drag started under the threshold`)
  move(left(30)); assert.equal(root.begun, 1, `${id}: drag didn't start`)
  root.cancelDrag()                       // Escape
  move(left(60)); move(left(90))
  assert.equal(root.begun, 1, `${id}: drag restarted after Escape in the same press`)
  release(left(90)); area.pressed = false; click(left(90))
  assert.equal(root.ended, 0, `${id}: release after Escape ended a drag`)
  assert.deepEqual(root.actions, [], `${id}: click after Escape did something`)

  area.pressed = true; press(left())
  move(left(30)); assert.equal(root.begun, 2, `${id}: fresh press can't drag`)
  console.log(`ok ${id}`)
}

check("boxMouse", "windowBox")
check("favHover", "favourite")
check("hover", "tile")
