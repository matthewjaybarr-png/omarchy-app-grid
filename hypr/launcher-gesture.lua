-- matthewjaybarr.app-grid: GNOME-style 3-finger swipe. Up opens the app grid, down
-- closes it, and the grid follows the fingers the whole way.
--
-- Not loaded from here. scripts/dev-link.sh links it into
-- ~/.local/state/omarchy/toggles/hypr/, which Omarchy's toggle loader
-- (default/hypr/toggles.lua) sources on every Hyprland reload.
--
-- Hyprland 0.56 calls the start/update/finish table for every trackpad
-- event. `delta` is per-event, so travel is accumulated here; turning it
-- into a fraction of the animation needs the screen height, which only the
-- QML side knows. hl.dsp.event puts a `custom>>` line on the event socket
-- the launcher already listens to, with no process spawn at touchpad rate.
-- Pattern borrowed from bergdahlchi.omari/hypr/omari-overview.lua.

-- Omari's niri mode binds 3-finger VERTICAL for workspaces. up/down collide
-- with vertical, and whichever registers second is rejected with a config
-- error, so stand aside while that mode is on. Temporary until the niri bits
-- worth keeping live in Omarchy proper.
local toggles = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
  .. "/omarchy/toggles/hypr"
local omari_mode = io.open(toggles .. "/omari-mode.lua", "r")
if omari_mode then
  omari_mode:close()
  return
end

local function emit(msg)
  hl.dispatch(hl.dsp.event(msg))
end

-- `sign` turns the axis into travel that grows as the swipe proceeds:
-- up is negative y, down is positive.
local function tracker(prefix, sign)
  local travel = 0

  local function report(e)
    travel = travel + sign * e.delta.y
    emit(string.format("%s-at %.1f %d", prefix, travel, e.time_ms))
  end

  return {
    start = function(e)
      travel = 0
      emit(prefix .. "-begin")
      report(e)
    end,
    update = report,
    finish = function(e)
      -- Commit vs. spring back is decided in QML, which knows how far the
      -- grid got. Send the lift time so a swipe that stopped on the pad
      -- before lifting isn't mistaken for a flick.
      emit(string.format("%s-end %d %d", prefix, e.cancelled and 1 or 0, e.time_ms))
      travel = 0
    end,
  }
end

hl.gesture({ fingers = 3, direction = "up", action = tracker("omarchy-app-grid:up", -1) })
hl.gesture({ fingers = 3, direction = "down", action = tracker("omarchy-app-grid:down", 1) })
