# Preview setting

## Why

Live window previews in the workspace cards are the plugin's only ongoing
cost while the grid is open (about 12–15% of a core with four windows on the
test laptop). Older or hot-running machines need a cheaper option.

## Goals

- A setting with three modes: **Live** (today's behaviour), **Still** (one
  frame per window when the cards appear) and **Icons only** (no capture).
- Default Live, so existing users see no change.
- Saved with the other preferences in `~/.local/state/omarchy/omarchy-app-grid.json`.

Non-goals: per-workspace or per-window settings, a frame-rate slider, changing
the folded strip (it already captures nothing).

## Approaches

- A. Live / Icons only. Simplest, but drops the picture entirely.
- B. Live / Still / Icons only. **Picked by Matt.** Still keeps the preview
  useful at near-zero ongoing cost.

## Design

- New pref `previews: "live" | "still" | "off"`, default `"live"`; any other
  value reads as live.
- `ScreencopyView` (LauncherView.qml, workspace cards): `live` is true only in
  live mode; `captureSource` is null in off mode. With `live: false` it grabs
  one frame when the source is set. The existing icon fallback covers off.
- Settings menu (gear): after the two click-behaviour items, three ✓ items:
  "Live previews", "Still previews", "No previews (icons only)".
- README: the previews paragraph and the screencopy cost note mention the setting.
- A Node check extracts the menu and action code and asserts the modes.

Left to the builder: exact menu separator styling, test file placement.
