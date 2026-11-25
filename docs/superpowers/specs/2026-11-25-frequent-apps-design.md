# Frequent apps

## Why

Matt reaches the apps he uses daily by paging through the grid or typing.
The apps he actually uses should be on screen when the grid opens, and
typing should land on them sooner.

## Goals

- A **Frequent** row of the most-used apps between the workspace strip and
  the grid, shown while the search is empty.
- Search ranks used apps first among equally good matches.
- One usage record feeds both, saved in the prefs file.

Non-goals: tracking launches made outside the grid (Walker, keybindings,
terminals); dragging tiles out of the Frequent row; a per-app "forget" item.

Anti-goals: icons that shuffle on every launch; a used app outranking a
better match (typing "fi" must not put Signal above Files).

## Approaches

- A. Recent row (last launched first). Simple, but reorders on every launch.
- B. Frequent row, ranked by use that fades over time. Stable positions.
  **Picked by Matt.**
- C. Search boost only, no new row. **Picked by Matt alongside B.**

## Design

- **Recording.** Counts as use: launching an app from the grid, dash,
  Frequent row or search, and clicking an open app to switch to it.
  Stored as `prefs.usage`: `{ "<desktop id>": [score, lastUsedMs] }`.
  On use, `score = score * 0.5^(days since lastUsed / 7) + 1` (a 7-day
  half-life). Keep the 40 highest; drop the rest on write.
- **Row.** Up to `columns` apps by decayed score, highest first. Leaves out
  hidden apps, pinned favourites (the dash already shows them) and ids that
  no longer resolve. Apps inside folders appear on their own. No row until
  there is usage, and none while searching; when it shows, the grid gives
  up one row (8×4 → 8×3 on the test laptop).
- **Row tiles.** The shared AppTile: click launches/switches (existing
  rules), middle/Ctrl-click launches new, right-click shows the app menu.
- **Keyboard.** `Up` from the grid's top row enters the Frequent row,
  `Up` again enters the workspace strip; `Down` goes back. Left/Right move
  within the row, Enter launches. Without a row, today's behaviour.
- **Search boost.** Rows keep the library's match kind (name prefix,
  id prefix, name substring, …). Within the same kind, higher usage sorts
  first; across kinds, the library's order stands.
- **Setting.** Gear menu ✓ "Show frequent apps", on by default
  (`prefs.showFrequent`). Off hides the row; usage still records and still
  boosts search.
- **README** names the row, the setting, and that only grid launches count.

## Builder's calls (Claude's, flagged for Matt)

- 7-day half-life, 40-entry cap, row length = grid columns.
- Favourites excluded from the row; setting on by default.
- How "match kind" is derived from the library's scores (its score bands).
