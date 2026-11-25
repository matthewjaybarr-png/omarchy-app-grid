# Frequent Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record app use in the prefs file, rank used apps first within a search match band, and show a Frequent row above the grid.

**Architecture:** Pure functions in `LauncherView.qml` (`decayedScore`, `bumpUsage`, `frequentIds`, `boostRows`) hold the logic so Node can run their real bodies. `launchEntry`/`launchOnWorkspace` record use; `refreshApps` boosts search rows; a new row between the strip hint and the grid shows `frequentEntries`, with a `"frequent"` keyboard zone.

**Tech Stack:** QML (Quickshell), Node assertion checks.

**Spec:** `docs/superpowers/specs/2026-11-25-frequent-apps-design.md`

## Global Constraints

- `prefs.usage`: `{ "<desktop id>": [score, lastUsedMs] }`, default `({})`; `prefs.showFrequent: true`.
- Decay: `score * 0.5^(days / 7)`; use adds 1; keep the 40 highest.
- Row length = `root.columns`; excludes hidden apps, favourites and unresolved ids.
- Menu label exactly "Show frequent apps" with the `"✓  "` / `"   "` prefix.
- Work on `next`; no push until 0.5.5 (#15924) is approved.

## Review Focus

- Prefs file without `usage`/`showFrequent`, or `usage` hand-edited to junk (`[]`, `{"x": "a"}`) → no row, no exception.
- A favourite or hidden app with the top score → absent from the row; the next app fills in.
- Uninstalled app still in `usage` → skipped, not a blank tile.
- Typing "fi" with Signal used heavily and Files never → Files first (band beats usage).
- Row appears/disappears as you type → grid rows recompute, selection stays valid.

---

### Task 1: Usage record and search boost

**Files:**
- Modify: `LauncherView.qml` (prefs JsonAdapter ~355; `launchEntry` ~518; `launchOnWorkspace` ~1100; `refreshApps` ~247)
- Create: `tests/frequent-apps.mjs`

**Interfaces:**
- Produces:
  - `function decayedScore(rec, now): number` — `rec` is `[score, lastMs]`; anything malformed → 0.
  - `function bumpUsage(usage, id, now): object` — new object, never mutates; drops malformed records; caps at 40 by decayed score.
  - `function frequentIds(usage, now, limit, skip): [string]` — ids by decayed score desc, ties by id; `skip(id)` true drops one.
  - `function boostRows(rows, usage, now): rows` — stable sort by `Math.floor(row.score / 500)` desc, then decayed usage desc, then original order.
  - `function recordUse(id)` — `prefs.usage = root.bumpUsage(prefs.usage, String(id), Date.now())`.

- [ ] **Step 1: Write `tests/frequent-apps.mjs`** with the `block(start)` extractor from `tests/preview-mode.mjs`, building each function via `new Function`. Assert, with `DAY = 864e5`, `now = 100 * DAY`:
  - `decayedScore([4, now - 7*DAY], now) === 2`; `decayedScore("a", now) === 0`; `decayedScore(undefined, now) === 0`.
  - `bumpUsage({}, "a", now).a` deep-equals `[1, now]`; bumping `{a:[2, now-7*DAY]}` gives `a[0] === 2`; input object unchanged.
  - 41 ids bumped once each (id `i` at `now + i`) → 40 keys, `"0"` gone; `bumpUsage({x:"bad"}, "a", now)` has no `x`.
  - `frequentIds({a:[1,now], b:[3,now], c:[2,now]}, now, 2, () => false)` → `["b","c"]`; with `skip = id => id === "b"` → `["c","a"]`; `frequentIds([], now, 8, ...)` → `[]`.
  - `boostRows` on rows `[{entry:{id:"files"},score:9995},{entry:{id:"firefox"},score:9993},{entry:{id:"signal"},score:7990}]` with usage `{firefox:[5,now], signal:[50,now]}` → ids `["firefox","files","signal"]`.
  - `launchEntry` body matches `/root\.recordUse\(entry\.id\)/` on both the switch-to-window path and the launch path (count ≥ 2); `launchOnWorkspace` body contains `root.recordUse(`.
  - `refreshApps` body matches `/root\.boostRows\(/`.
- [ ] **Step 2:** `node tests/frequent-apps.mjs` → FAIL (`function decayedScore( not found`).
- [ ] **Step 3: Implement** the two prefs properties, the five functions, `recordUse` calls (not for folders or window entries), and `rows = root.boostRows(rows, prefs.usage, Date.now())` when the query is non-empty.
- [ ] **Step 4:** `node tests/frequent-apps.mjs` → `ok frequent-apps`; add `check node tests/frequent-apps.mjs` to the local AGENTS.md quiet check; run it all → every line `ok`.
- [ ] **Step 5: Commit** `git add LauncherView.qml tests/frequent-apps.mjs` — "Record app use; rank used apps first within a search match".

### Task 2: Frequent row, keyboard zone and setting

**Files:**
- Modify: `LauncherView.qml` (`rows` ~762; menuItems settings branch ~539; `runMenuAction`; key handler ~1699–1745; layout between strip hint and `viewport` ~2090)
- Modify: `tests/frequent-apps.mjs`, `tests/preview-mode.mjs` (settings menu now has 6 items), `README.md`

**Interfaces:**
- Consumes: `frequentIds`, `recordUse` (Task 1).
- Produces:
  - `property real usageNow` — set to `Date.now()` in `prepare()`, so the row doesn't reorder while open.
  - `readonly property var frequentEntries` — `frequentIds(prefs.usage, root.usageNow, root.columns, skip)` mapped through `entryById`, where `skip` drops hidden, favourite and unresolved ids.
  - `readonly property bool frequentShown` — `prefs.showFrequent !== false && root.query.length === 0 && root.frequentEntries.length > 0`.
  - `property int frequentIndex`; zone value `"frequent"`; `function frequentEnter(): bool`.
  - Menu action `"frequent"` toggles `prefs.showFrequent`.

- [ ] **Step 1: Extend tests.** In `frequent-apps.mjs`: the settings branch (stubbing `root.previewMode` and `prefs`) with `showFrequent: false` contains `"   Show frequent apps"` (action `"frequent"`), with `{}` contains `"✓  Show frequent apps"`; `rows` binding text matches `/root\.frequentShown \? root\.cellHeight : 0/`; key handler text contains `root.zone === "frequent"` and `root.frequentEnter()`. In `preview-mode.mjs`, expect the new 6th label `"✓  Show frequent apps"` and 3 ticks by default.
- [ ] **Step 2:** both tests FAIL.
- [ ] **Step 3: Implement.**
  - `rows` subtracts `(root.frequentShown ? root.cellHeight : 0)` from the available height.
  - The row: `cellWidth × cellHeight` tiles centred under the strip hint, the grid's `viewport.y` moves down by `cellHeight` while shown. Each tile shows icon, name and running dot like AppTile (no drag; AppTile is slot/drag-bound), highlights when `zone === "frequent" && frequentIndex === index`, left/middle click → `root.launchEntry(modelData, root.wantsFresh(mouse))`, right-click → `root.openMenu(modelData, scenePos, "grid")`.
  - Keys: grid `Up` from the top row → `frequentEnter()` if shown, else `stripEnter()`. In `"frequent"`: Left/Right step (clamped), Enter/Ctrl+Enter launch, Up → `stripEnter()`, Down/Escape → zone `"grid"` and `moveSelection(0, 0)`. Strip `Down` → `frequentEnter()` if shown, else today's grid return. Any query change already resets zone to grid.
  - Settings menu gets "Show frequent apps" after the preview items.
- [ ] **Step 4:** both tests pass; full quiet check `ok`.
- [ ] **Step 5: Live check** after `omarchy restart shell` (back up and restore the prefs file around it): launch two apps from the grid, reopen → row shows them, grid 8×3; typing hides the row; Up/Down walk grid → row → strip → row → grid; gear toggle hides/shows the row; pinning a row app removes it from the row; Escape cancels a grid drag. No real-screen captures.
- [ ] **Step 6: README** — a **Frequent** paragraph after Favourites: the row, the search ordering, the gear setting, and that only launches from the grid count; mention `usage` in the prefs-file sentence.
- [ ] **Step 7: Commit** `git add LauncherView.qml tests/ README.md docs/superpowers` — "Frequent apps row".
