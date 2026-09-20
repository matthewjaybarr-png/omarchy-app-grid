import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.Commons

// GNOME-style app grid. Everything on screen is a function of `progress`
// (0 = gone, 1 = fully open), so the keyboard path animates it and the
// touchpad path drives it 1:1 from hypr/launcher-gesture.lua.
Item {
  id: root

  // Injected by omarchy-shell.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "matt.launcher"

  // The shell is meant to hand `menu` plugins an app-library facade, but on
  // Omarchy 4.0.4 it arrives null for this third-party plugin (the other
  // facade hooks work). Until that's sorted, run Omarchy's own AppLibrary.qml
  // here: same hidden-entry rules, icon index, and launch feedback.
  readonly property var appLibrary: root.shell && root.shell.appLibrary
    ? root.shell.appLibrary : ownLibrary.item

  Loader {
    id: ownLibrary
    active: !(root.shell && root.shell.appLibrary)
    source: "file://" + (root.omarchyPath || "/usr/share/omarchy") + "/shell/services/AppLibrary.qml"
  }

  // ---- sharp icons ----
  //
  // Omarchy's icon index keeps whichever file find() returns first for a name,
  // and inside hicolor that is usually the 16x16 PNG — fine on a 24px bar,
  // mush at 96px. SVGs are already right (its scan emits them first), so this
  // only overrides names that resolved to a PNG, picking the biggest one.

  property var pngIndex: ({})
  property var pendingPngIndex: ({})

  function pngScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for base in $dirs; do',
      '  [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.png" 2>/dev/null;',
      'done;',
      'find /usr/share/pixmaps -maxdepth 1 -name "*.png" 2>/dev/null'
    ].join(' ')
  }

  // "…/256x256/apps/x.png" -> 256, "…/48x48@2x/…" -> 96. Sizeless dirs
  // (/usr/share/pixmaps) score 48, the usual size there, so a real 256 wins
  // and a real 16 does not.
  function pngPixels(path) {
    var m = /\/(\d+)x\d+(?:@(\d+)x)?\//.exec(path)
    if (!m) return 48
    return parseInt(m[1], 10) * (m[2] ? parseInt(m[2], 10) : 1)
  }

  function indexPngLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var file = value.slice(value.lastIndexOf("/") + 1)
    var name = file.slice(0, file.lastIndexOf("."))
    if (name.length === 0) return
    var size = root.pngPixels(value)
    var best = root.pendingPngIndex[name]
    if (!best || size > best.size) root.pendingPngIndex[name] = { path: value, size: size }
  }

  function iconSource(icon) {
    if (!root.appLibrary) return ""
    var source = root.appLibrary.iconSource(icon)
    var best = root.pngIndex[String(icon || "")]
    if (best && /\.png$/i.test(String(source))) return Util.fileUrl(best.path)
    return source
  }

  Process {
    id: pngScan
    command: ["bash", "-c", root.pngScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexPngLine(line) } }
    onStarted: root.pendingPngIndex = ({})
    // Swapping the whole map re-evaluates every iconSource() binding at once.
    onExited: root.pngIndex = root.pendingPngIndex
  }

  // Rescan when Omarchy's own index changes, so a freshly installed app's icon
  // appears at the same moment its entry does.
  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onIconIndexChanged() { if (!pngScan.running) pngScan.running = true }
  }

  Component.onCompleted: pngScan.running = true

  // ---- host lifecycle ----
  // The host reads `opened` for toggle(). It is the *target* state: it drops
  // to false as soon as a close starts, so a keypress during the close
  // animation reopens instead of being swallowed by a second hide().

  property bool opened: false

  function open(payloadJson) {
    if (root.opened) return
    root.prepare()
    root.interactive = true
    root.animateTo(1)
  }

  function close() {
    root.dismiss()
  }

  function ping() { return "ok" }

  // omarchy-shell shell call matt.launcher debugState x
  function debugState() {
    return JSON.stringify({
      shell: !!root.shell,
      appLibrary: !root.appLibrary ? "none" : ownLibrary.item === root.appLibrary ? "own" : "shell",
      apps: root.apps.length,
      all: root.appLibrary ? root.appLibrary.sortedEntries("").length : -1,
      opened: root.opened, progress: root.progress, page: root.page,
      columns: root.columns, rows: root.rows, screen: [root.screenWidth, root.screenHeight],
      pngIndex: Object.keys(root.pngIndex).length,
      menu: root.menuEntry ? String(root.menuEntry.id) : null,
      menuArmed: root.menuArmed,
      searchFocus: searchInput.activeFocus,
      // Last scroll event seen, for working out whether two-finger paging is
      // reaching the surface at all.
      wheel: root.lastWheel
    })
  }

  // Closing from inside (Escape, a launch, a click on empty space) also has
  // to clear the host's open bookkeeping. hide() calls back into close(),
  // which is a no-op by then.
  function requestClose() {
    root.dismiss()
    if (root.shell) root.shell.hide(root.pluginId)
  }

  function dismiss() {
    if (!root.opened) return
    root.opened = false
    root.interactive = false
    root.gestureMode = ""
    root.animateTo(0)
  }

  // ---- state ----

  property real progress: 0
  property bool interactive: false
  property var targetScreen: null
  property string wallpaperPath: ""
  property string query: ""
  property var apps: []
  property int page: 0
  property int selectedIndex: -1
  readonly property int openMs: 260

  function prepare() {
    root.opened = true
    root.targetScreen = root.pickScreen()
    wallpaperProbe.running = true
    root.query = ""
    root.page = 0
    root.selectedIndex = -1
    root.dragOffset = 0
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.refreshApps()
  }

  function pickScreen() {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  function refreshApps() {
    // sortedEntries() returns ranked rows ({entry, score, key, name}).
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(root.query) : []
    var entries = rows.map(function(row) { return row.entry })
    // Hidden apps drop out of the grid but still turn up in search, dimmed, so
    // there is always a way back to the menu that unhides them.
    if (root.query.length === 0)
      entries = entries.filter(function(entry) { return !root.isHidden(entry.id) })
    root.apps = entries
    if (root.page >= root.pageCount) root.page = Math.max(0, root.pageCount - 1)
  }

  // ---- pinned and hidden apps ----
  //
  // Omarchy has no per-user hide list (its launcher.hides lives in /usr/share,
  // and appLibrary.remove() is the *uninstaller*), so both lists are ours and
  // affect nothing outside this launcher.

  readonly property var favourites: prefs.favourites || []
  readonly property var hidden: prefs.hidden || []

  function isFavourite(id) { return root.favourites.indexOf(String(id)) >= 0 }
  function isHidden(id) { return root.hidden.indexOf(String(id)) >= 0 }

  function withItem(list, id, present) {
    var next = (list || []).filter(function(v) { return v !== String(id) })
    if (present) next.push(String(id))
    return next
  }

  function setFavourite(id, on) { prefs.favourites = root.withItem(root.favourites, id, on) }

  function setHidden(id, on) {
    prefs.hidden = root.withItem(root.hidden, id, on)
    if (on) prefs.favourites = root.withItem(root.favourites, id, false)
    root.refreshApps()
  }

  FileView {
    id: prefsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/matt-launcher.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    // No file yet on first run; the adapter defaults stand in until a pin.
    onLoadFailed: function(error) { if (error === FileViewError.FileNotFound) writeAdapter() }

    JsonAdapter {
      id: prefs
      property var favourites: []
      property var hidden: []
    }
  }

  // Entries for the favourites row, in pinned order, skipping ids that no
  // longer resolve to an installed app.
  readonly property var favouriteEntries: {
    var all = root.appLibrary ? root.appLibrary.sortedEntries("") : []
    var byId = ({})
    for (var i = 0; i < all.length; i++) byId[String(all[i].entry.id)] = all[i].entry
    return root.favourites.map(function(id) { return byId[id] }).filter(function(e) { return !!e })
  }

  onQueryChanged: {
    // Typing breaks a `text:` binding, so the field is synced by hand.
    if (searchInput.text !== root.query) searchInput.text = root.query
    root.refreshApps()
    root.page = 0
    root.selectedIndex = root.query.length > 0 && root.apps.length > 0 ? 0 : -1
  }

  onInteractiveChanged: if (interactive) Qt.callLater(function() { searchInput.forceActiveFocus() })

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { if (root.opened) root.refreshApps() }
  }

  function launch(index) {
    root.launchEntry(root.apps[index])
  }

  function launchEntry(entry) {
    if (!entry || !root.appLibrary) return
    root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
    root.requestClose()
  }

  // ---- right-click menu ----

  property var menuEntry: null
  property point menuPos: Qt.point(0, 0)
  property bool menuArmed: false   // Uninstall asks twice before it bites.

  readonly property var menuItems: {
    var entry = root.menuEntry
    if (!entry) return []
    var id = String(entry.id)
    var items = [
      { label: root.isFavourite(id) ? "Unpin from favourites" : "Pin to favourites", action: "favourite" },
      { label: root.isHidden(id) ? "Show in launcher" : "Hide from launcher", action: "hide" }
    ]
    items.push(root.menuArmed
      ? { label: "Really uninstall?", action: "uninstall", danger: true }
      : { label: "Uninstall…", action: "arm", danger: true })
    return items
  }

  function openMenu(entry, scenePos) {
    root.menuEntry = entry
    root.menuArmed = false
    root.menuPos = scenePos
  }

  function closeMenu() {
    root.menuEntry = null
    root.menuArmed = false
  }

  function runMenuAction(action) {
    var entry = root.menuEntry
    if (!entry) return
    var id = String(entry.id)
    switch (action) {
    case "favourite":
      root.setFavourite(id, !root.isFavourite(id))
      break
    case "hide":
      root.setHidden(id, !root.isHidden(id))
      break
    case "arm":
      // Omarchy's remover deletes the desktop file, or runs pacman -Rns /
      // flatpak uninstall in a terminal. Worth a second click.
      root.menuArmed = true
      return
    case "uninstall":
      if (root.appLibrary) root.appLibrary.remove(id, root.appLibrary.entryName(entry))
      root.requestClose()
      break
    }
    root.closeMenu()
  }

  // ---- open/close animation ----

  NumberAnimation {
    id: ramp
    target: root
    property: "progress"
    easing.type: Easing.OutCubic
  }

  function animateTo(target) {
    ramp.stop()
    ramp.from = root.progress
    ramp.to = target
    ramp.duration = Math.max(120, Math.round(root.openMs * Math.abs(target - root.progress)))
    ramp.start()
  }

  // ---- touchpad gesture ----
  // hypr/launcher-gesture.lua sends `matt-launcher:<up|down>-<begin|at|end>`
  // on Hyprland's event socket. Listening is deliberately not gated on
  // `opened`: the first event of an opening swipe arrives while closed.

  property string gestureMode: ""   // "", "open", "close"
  property real gestureBase: 0
  property real gestureVelocity: 0  // px/ms, smoothed, positive = forward
  property real gestureLastTravel: 0
  property real gestureLastTime: 0
  readonly property real gestureDistance: Math.max(Style.space(180), root.screenHeight * 0.3)
  readonly property real gestureCommitRatio: 0.32
  readonly property real gestureFlickSpeed: 0.4
  readonly property int gestureIdleMs: 50

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var data = String(event.data || "")
      if (data.indexOf("matt-launcher:") !== 0) return
      var parts = data.split(" ")
      var head = parts[0].substring("matt-launcher:".length)
      var mode = head.indexOf("up-") === 0 ? "open" : "close"
      var stage = head.substring(head.indexOf("-") + 1)
      if (stage === "begin") root.gestureBegin(mode)
      else if (stage === "at") root.gestureAt(mode, Number(parts[1]), Number(parts[2]))
      else if (stage === "end") root.gestureEnd(mode, parts[1] === "1", Number(parts[2]))
    }
  }

  function gestureBegin(mode) {
    if (root.gestureMode !== "") return
    if (mode === "open") {
      if (root.opened) return
      // Catch a launcher that is still animating shut instead of restarting it.
      if (root.progress > 0) root.opened = true
      else root.prepare()
    } else {
      if (!root.opened) return
    }
    ramp.stop()
    root.gestureMode = mode
    root.gestureBase = root.progress
    root.gestureVelocity = 0
    root.gestureLastTravel = 0
    root.gestureLastTime = 0
    root.interactive = false
  }

  function gestureAt(mode, travel, timeMs) {
    if (root.gestureMode !== mode) return
    if (root.gestureLastTime > 0 && timeMs > root.gestureLastTime) {
      root.gestureVelocity = 0.5 * root.gestureVelocity
        + 0.5 * (travel - root.gestureLastTravel) / (timeMs - root.gestureLastTime)
    }
    root.gestureLastTravel = travel
    root.gestureLastTime = timeMs
    var sign = mode === "open" ? 1 : -1
    root.progress = Math.max(0, Math.min(1, root.gestureBase + sign * travel / root.gestureDistance))
  }

  function gestureEnd(mode, cancelled, timeMs) {
    if (root.gestureMode !== mode) return
    root.gestureMode = ""
    // Fingers that stopped on the pad before lifting carry no flick.
    var resting = root.gestureLastTime > 0 && timeMs > 0
      && (timeMs - root.gestureLastTime) > root.gestureIdleMs
    var speed = resting ? 0 : root.gestureVelocity
    var moved = mode === "open" ? root.progress : 1 - root.progress
    var commit = !cancelled && speed > -root.gestureFlickSpeed
      && (moved >= root.gestureCommitRatio || speed >= root.gestureFlickSpeed)
    var wantOpen = mode === "open" ? commit : !commit
    if (wantOpen) {
      root.interactive = true
      root.animateTo(1)
    } else {
      root.requestClose()
      // requestClose() is a no-op when a cancelled open never set `opened`
      // back; make sure the surface still animates away.
      root.animateTo(0)
    }
  }

  // ---- grid geometry ----

  // Sized from the target monitor, not the window: the surface isn't mapped
  // yet when a swipe begins, and an unmapped PanelWindow reports 100x100.
  readonly property real screenWidth: root.targetScreen ? root.targetScreen.width : 1280
  readonly property real screenHeight: root.targetScreen ? root.targetScreen.height : 800

  readonly property int iconSize: Math.round(Math.max(48, Math.min(96, root.screenHeight / 11)))
  readonly property int cellWidth: Math.round(iconSize * 1.75)
  readonly property int cellHeight: Math.round(iconSize + Style.font.body * 2 + Style.space(28))
  readonly property int columns: Math.max(4, Math.min(8, Math.floor(root.screenWidth * 0.84 / cellWidth)))
  readonly property int rows: Math.max(2, Math.min(5, Math.floor((root.screenHeight - Style.space(240)) / cellHeight)))
  readonly property int perPage: columns * rows
  readonly property int pageCount: Math.max(1, Math.ceil(apps.length / perPage))

  function select(index) {
    if (root.apps.length === 0) return
    var next = Math.max(0, Math.min(root.apps.length - 1, index))
    root.selectedIndex = next
    root.page = Math.floor(next / root.perPage)
  }

  function moveSelection(dx, dy) {
    if (root.selectedIndex < 0) { root.select(root.page * root.perPage); return }
    root.select(root.selectedIndex + dx + dy * root.columns)
  }

  function goToPage(next) {
    root.page = Math.max(0, Math.min(root.pageCount - 1, next))
    if (root.selectedIndex >= 0) root.select(root.page * root.perPage)
  }

  // ---- page swiping (two-finger touchpad follows the fingers, wheel steps) ----

  property real dragOffset: 0
  property bool pageDragging: false
  property string dragAxis: ""
  property real wheelAccumulator: 0
  property var lastWheel: null

  function handleWheel(event) {
    var touchpad = event.phase !== Qt.NoScrollPhase || event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0
    root.lastWheel = {
      phase: event.phase, touchpad: touchpad,
      pixel: [event.pixelDelta.x, event.pixelDelta.y],
      angle: [event.angleDelta.x, event.angleDelta.y]
    }
    if (!touchpad) {
      root.wheelAccumulator += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
      while (root.wheelAccumulator <= -120) { root.goToPage(root.page + 1); root.wheelAccumulator += 120 }
      while (root.wheelAccumulator >= 120) { root.goToPage(root.page - 1); root.wheelAccumulator -= 120 }
      return
    }
    if (event.phase === Qt.ScrollEnd) { root.settlePageDrag(); return }
    if (root.dragAxis === "") {
      if (Math.abs(event.pixelDelta.x) < 1 && Math.abs(event.pixelDelta.y) < 1) return
      root.dragAxis = Math.abs(event.pixelDelta.x) >= Math.abs(event.pixelDelta.y) ? "x" : "y"
    }
    root.pageDragging = true
    root.dragOffset += root.dragAxis === "x" ? event.pixelDelta.x : event.pixelDelta.y
    dragSettle.restart()
  }

  function settlePageDrag() {
    dragSettle.stop()
    if (!root.pageDragging) return
    var threshold = viewport.width * 0.15
    var next = root.page
    if (root.dragOffset < -threshold) next = root.page + 1
    else if (root.dragOffset > threshold) next = root.page - 1
    root.pageDragging = false
    root.dragAxis = ""
    root.dragOffset = 0
    root.goToPage(next)
  }

  // Not every device reports ScrollEnd; settle after a quiet spell too.
  Timer { id: dragSettle; interval: 140; onTriggered: root.settlePageDrag() }

  // Rubber-band past the first and last page.
  function resisted(offset) {
    var atStart = root.page === 0 && offset > 0
    var atEnd = root.page === root.pageCount - 1 && offset < 0
    return atStart || atEnd ? offset * 0.3 : offset
  }

  // ---- wallpaper ----

  Process {
    id: wallpaperProbe
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: SplitParser {
      onRead: function(line) { if (line.trim().length > 0) root.wallpaperPath = line.trim() }
    }
  }

  // ---- surface ----

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.opened || root.progress > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "matt-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.interactive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Blurred wallpaper, rendered once into a layer so fading it costs nothing.
    Item {
      anchors.fill: parent
      opacity: root.progress
      layer.enabled: true

      Image {
        id: wallpaper
        anchors.fill: parent
        visible: false
        source: root.wallpaperPath ? Util.fileUrl(root.wallpaperPath) : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.round(root.screenWidth / 4)
        asynchronous: true
        cache: true
      }

      MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        autoPaddingEnabled: false
      }

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.55)
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.requestClose()
    }

    Item {
      id: content
      anchors.fill: parent
      opacity: root.progress
      scale: 0.94 + 0.06 * root.progress
      transform: Translate { y: (1 - root.progress) * root.screenHeight * 0.08 }

      // Search pill
      Rectangle {
        id: searchPill
        width: Math.min(Style.space(460), root.screenWidth * 0.5)
        height: Style.space(40)
        radius: height / 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.screenHeight * 0.07)
        color: Util.alpha(Color.background, 0.8)
        border.width: 1
        border.color: Util.alpha(Color.foreground, searchInput.activeFocus ? 0.4 : 0.15)

        MouseArea { anchors.fill: parent; onClicked: searchInput.forceActiveFocus() }

        Text {
          anchors.fill: searchInput
          visible: root.query.length === 0
          text: "Type to search"
          color: Util.alpha(Color.foreground, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
        }

        TextInput {
          id: searchInput
          anchors.fill: parent
          anchors.leftMargin: Style.space(18)
          anchors.rightMargin: Style.space(18)
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          color: Color.foreground
          selectionColor: Util.alpha(Color.accent, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          clip: true
          onTextEdited: root.query = text

          Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Escape:
              if (root.menuEntry) root.closeMenu()
              else if (root.query.length > 0) root.query = ""
              else root.requestClose()
              break
            case Qt.Key_Return:
            case Qt.Key_Enter:
              root.launch(root.selectedIndex >= 0 ? root.selectedIndex : 0)
              break
            case Qt.Key_Left: root.moveSelection(-1, 0); break
            case Qt.Key_Right: root.moveSelection(1, 0); break
            case Qt.Key_Up: root.moveSelection(0, -1); break
            case Qt.Key_Down: root.moveSelection(0, 1); break
            case Qt.Key_Tab: root.moveSelection(1, 0); break
            case Qt.Key_Backtab: root.moveSelection(-1, 0); break
            case Qt.Key_PageDown: root.goToPage(root.page + 1); break
            case Qt.Key_PageUp: root.goToPage(root.page - 1); break
            default: return
            }
            event.accepted = true
          }
        }
      }

      // Paged grid
      Item {
        id: viewport
        width: root.columns * root.cellWidth
        height: root.rows * root.cellHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: searchPill.y + searchPill.height + Style.space(36)
        clip: true

        Row {
          x: -root.page * viewport.width + root.resisted(root.dragOffset)
          Behavior on x {
            enabled: !root.pageDragging
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
          }

          Repeater {
            model: root.pageCount

            Item {
              id: pageGrid
              required property int index
              readonly property int count: Math.max(0, Math.min(root.perPage, root.apps.length - index * root.perPage))
              width: viewport.width
              height: viewport.height

              // A short single row (typical of search results) sits centred, as in GNOME.
              Grid {
                x: pageGrid.count < root.columns ? Math.round((viewport.width - pageGrid.count * root.cellWidth) / 2) : 0
                columns: root.columns

                Repeater {
                  model: root.apps.slice(pageGrid.index * root.perPage, (pageGrid.index + 1) * root.perPage)

                  AppTile {
                    required property var modelData
                    required property int index
                    entry: modelData
                    globalIndex: pageGrid.index * root.perPage + index
                  }
                }
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.apps.length === 0
          text: root.query.length > 0 ? "No apps match “" + root.query + "”" : ""
          color: Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }
      }

      // Scroll catcher. A WheelHandler parented straight to the window's
      // content item never gets delivered anything (clicks still work), so it
      // lives on a real full-size Item laid over the grid. A plain Item does
      // not accept mouse buttons, so tiles below stay clickable.
      Item {
        anchors.fill: parent
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) { root.handleWheel(event) }
        }
      }

      // Page dots
      Row {
        visible: root.pageCount > 1
        spacing: Style.space(10)
        anchors.horizontalCenter: parent.horizontalCenter
        y: viewport.y + viewport.height + Style.space(24)

        Repeater {
          model: root.pageCount

          Rectangle {
            required property int index
            width: Style.space(8)
            height: width
            radius: width / 2
            color: Util.alpha(Color.foreground, index === root.page ? 0.9 : 0.3)
            Behavior on color { ColorAnimation { duration: 150 } }

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              onClicked: root.goToPage(parent.index)
            }
          }
        }
      }

      // Favourites row (GNOME's dash), hidden while searching.
      Rectangle {
        id: dash
        visible: root.favouriteEntries.length > 0 && root.query.length === 0
        width: dashRow.width + Style.space(16)
        height: dashRow.height + Style.space(16)
        radius: Style.space(22)
        color: Util.alpha(Color.background, 0.55)
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.12)
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.screenHeight - height - Style.space(28)

        Row {
          id: dashRow
          anchors.centerIn: parent
          spacing: Style.space(6)

          Repeater {
            model: root.favouriteEntries

            Item {
              id: favourite
              required property var modelData
              readonly property int size: Math.round(root.iconSize * 0.72)
              width: size + Style.space(14)
              height: size + Style.space(14)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(14)
                color: favHover.containsMouse ? Util.alpha(Color.foreground, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              Image {
                anchors.centerIn: parent
                width: favourite.size
                height: favourite.size
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: root.iconSource(favourite.modelData.icon)
                asynchronous: true
                scale: favHover.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
              }

              MouseArea {
                id: favHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton)
                    root.openMenu(favourite.modelData, favourite.mapToItem(null, mouse.x, mouse.y))
                  else
                    root.launchEntry(favourite.modelData)
                }
              }
            }
          }
        }
      }
    }

    // Right-click menu. Outside `content` so it is not scaled by the open
    // animation, and above it so its catcher takes the next click.
    Item {
      anchors.fill: parent
      visible: !!root.menuEntry

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closeMenu()
      }

      Rectangle {
        id: menu
        readonly property real pad: Style.space(6)
        x: Math.max(Style.space(8), Math.min(root.menuPos.x, root.screenWidth - width - Style.space(8)))
        y: Math.max(Style.space(8), Math.min(root.menuPos.y, root.screenHeight - height - Style.space(8)))
        width: Style.space(232)
        height: menuColumn.height + pad * 2
        radius: Style.space(14)
        color: Util.alpha(Color.background, 0.97)
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.15)

        Column {
          id: menuColumn
          x: menu.pad
          y: menu.pad
          width: parent.width - menu.pad * 2

          Repeater {
            model: root.menuItems

            Rectangle {
              id: menuItem
              required property var modelData
              width: parent.width
              height: Style.space(34)
              radius: Style.space(10)
              color: itemHover.containsMouse ? Util.alpha(Color.foreground, 0.12) : "transparent"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                x: Style.space(12)
                width: parent.width - Style.space(24)
                elide: Text.ElideRight
                text: menuItem.modelData.label
                color: menuItem.modelData.danger ? "#e06c75" : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: itemHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.runMenuAction(menuItem.modelData.action)
              }
            }
          }
        }
      }
    }
  }

  component AppTile: Item {
    id: tile
    property var entry: null
    property int globalIndex: -1
    readonly property bool selected: root.selectedIndex === globalIndex
    // Hidden apps only ever appear here via search; dimmed, to say why they
    // are not in the grid.
    readonly property bool dimmed: tile.entry ? root.isHidden(tile.entry.id) : false
    width: root.cellWidth
    height: root.cellHeight
    opacity: tile.dimmed ? 0.45 : 1

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      radius: Style.space(18)
      color: tile.selected ? Util.alpha(Color.foreground, 0.16)
        : hover.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"
      Behavior on color { ColorAnimation { duration: 120 } }
    }

    Image {
      id: icon
      width: root.iconSize
      height: root.iconSize
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(14)
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: tile.entry ? root.iconSource(tile.entry.icon) : ""
      asynchronous: true
      scale: hover.pressed ? 0.92 : 1
      Behavior on scale { NumberAnimation { duration: 90 } }
    }

    Text {
      anchors.top: icon.bottom
      anchors.topMargin: Style.space(8)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      maximumLineCount: 1
      text: tile.entry && root.appLibrary ? root.appLibrary.entryName(tile.entry) : ""
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton)
          root.openMenu(tile.entry, tile.mapToItem(null, mouse.x, mouse.y))
        else
          root.launch(tile.globalIndex)
      }
    }
  }
}
