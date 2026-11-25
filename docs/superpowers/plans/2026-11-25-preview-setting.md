# Preview Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Live / Still / Icons-only setting for workspace-card window previews.

**Architecture:** One new `prefs` property drives the card `ScreencopyView`'s `live` and `captureSource`; the gear menu gets three ✓ items handled in `runMenuAction`.

**Tech Stack:** QML (Quickshell), Node assertion checks.

**Spec:** `docs/superpowers/specs/2026-11-25-preview-setting-design.md`

## Global Constraints

- Pref name `previews`, values `"live" | "still" | "off"`, default `"live"`; anything else reads as live.
- Menu labels exactly: "Live previews", "Still previews", "No previews (icons only)", with the existing `"✓  "` / `"   "` prefix style.
- Work on `next`; no push until 0.5.5 (#15924) is approved.

## Review Focus

- Prefs file from an older version (no `previews` key) → live, no write needed.
- Hand-edited bad value (`"foo"`, `true`) → live.
- Switching mode while the cards are open → takes effect at once (bindings).
- Still mode, cards folded then reopened → a fresh frame (captureSource goes null and back).
- Off mode → app icon centred, no capture (existing `hasContent` fallback).

---

### Task 1: Preview mode setting

**Files:**
- Modify: `LauncherView.qml` (prefs JsonAdapter ~361; `menuItems` ~539; `runMenuAction` ~607; card `ScreencopyView` ~1898)
- Create: `tests/preview-mode.mjs`
- Modify: `README.md` (previews paragraph ~85, screencopy note ~130), `AGENTS.md` quiet-check block

**Interfaces:**
- Produces: `prefs.previews: string`; `function previewMode(): string` returning `"live" | "still" | "off"`; menu actions `"previews-live" | "previews-still" | "previews-off"`.

- [ ] **Step 1: Write `tests/preview-mode.mjs`** using the `fn(name)` extractor from `tests/strip-keys.mjs`. Assert:
  - `previewMode()` with `prefs.previews` `undefined`, `"foo"`, `true` → `"live"`; `"still"` → `"still"`; `"off"` → `"off"`.
  - The `menuItems` settings branch (extract the binding text between `if (entry.isSettings) {` and its closing `}`) with `previews: "still"` gives 5 items; the 4th label is `"✓  Still previews"`, the 3rd `"   Live previews"`.
  - `runMenuAction` source contains `case "previews-off":` and sets `prefs.previews = action.slice(9)`.
  - The ScreencopyView block matches `/live: root.previewMode\(\) === "live"/` and `/captureSource: root.opened && root.stripExpanded && root.previewMode\(\) !== "off"/`.
- [ ] **Step 2:** `node tests/preview-mode.mjs` → FAIL (`previewMode not found`).
- [ ] **Step 3: Implement** the pref, `previewMode()`, the three menu items appended after the click items, the shared `case` in `runMenuAction`, and the two ScreencopyView bindings.
- [ ] **Step 4:** `node tests/preview-mode.mjs` → `ok preview-mode`; full AGENTS.md quiet check (with the new line added) all `ok`.
- [ ] **Step 5: Live check** after `omarchy restart shell`: each mode from the gear menu with cards open — live updates, still shows a frame that doesn't change, off shows icons; mode survives a shell restart (prefs file has `"previews"`); keyboard/search and drag cancel still work. No real-screen captures.
- [ ] **Step 6: README** — previews paragraph names the gear setting; the screencopy cost note says Still/Icons only cost ~0% after the first frame.
- [ ] **Step 7: Commit** on `next`: `git add LauncherView.qml tests/preview-mode.mjs README.md docs/superpowers` (AGENTS.md is untracked; edit it locally only) then commit "Preview setting: live, still or icons only". Do not push.
