import QtQuick

// Stable, host-facing shim. The real UI is LauncherView.qml.
//
// The plugin is keepLoaded (the gesture's first event arrives while closed),
// and the shell only swaps a keepLoaded plugin's code on a full restart: the
// live instance still holds its component when the cache is cleared. Loading
// the view from a fresh URL each time this shim is created makes
// `omarchy-shell shell rescanPlugins` pick up edits to LauncherView.qml.
// Edits to this file itself still need `omarchy restart shell`.
Item {
  id: root

  // Injected by omarchy-shell.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // Read by the host's toggle().
  readonly property bool opened: view.item ? view.item.opened : false

  function open(payloadJson) { if (view.item) view.item.open(payloadJson) }
  function close() { if (view.item) view.item.close() }
  function ping() { return view.item ? "ok" : "loading" }
  function debugState() { return view.item ? view.item.debugState() : String(view.status) }

  Loader {
    id: view
    source: Qt.resolvedUrl("LauncherView.qml") + "?v=" + Date.now()
    onLoaded: {
      item.omarchyPath = Qt.binding(function() { return root.omarchyPath })
      item.shell = Qt.binding(function() { return root.shell })
      item.manifest = Qt.binding(function() { return root.manifest })
    }
  }
}
