import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Dock-style Teams control, modelled on the macOS app:
//   - the icon is always present, like a Dock tile
//   - a badge carries the unread count, read from the window title
//   - hiding parks the window on a special workspace instead of quitting,
//     which is what Cmd+H does on macOS
//   - closing (SUPER+W) hides too, so the app keeps running in the background
//   - right-clicking opens a menu; quitting for real lives in there, because a
//     right-click that closes the app without asking is not a thing anyone expects
Panel {
  id: root
  moduleName: "fvargas.teams"
  ipcTarget: "fvargas.teams"
  // Panel's built-in IPC would claim show/hide/toggle for the *popup*. Those
  // names are already spoken for here -- SUPER+H and omarchy-teams-close call
  // them meaning the Teams *window* -- so this widget keeps its own handler.
  manageIpc: false

  // Panel, unlike BarWidget, has no broadcast(). An IPC target routes to a
  // single handler but a bar surface exists per monitor, so without this a
  // refresh would update one screen and leave the others stale.
  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method]()
    }
  }

  // ---- settings ----
  readonly property string appUrl: String(setting("url", "https://teams.microsoft.com"))
  readonly property string matchClass: String(setting("matchClass", "chrome-teams")).toLowerCase()
  readonly property bool autoDnd: setting("autoDnd", true) === true
  readonly property int pollInterval: Math.max(500, Number(setting("pollInterval", 2000)))
  readonly property string hideWorkspace: "special:teamshidden"
  // When set, unhiding returns Teams to this workspace instead of following
  // you around. Needed once a window rule pins Teams to a fixed workspace,
  // otherwise showing it would drag it off its assigned monitor.
  readonly property string homeWorkspace: String(setting("homeWorkspace", ""))

  // ---- window state, refreshed from hyprctl ----
  property string winAddress: ""
  property string winTitle: ""
  property string winWorkspace: ""

  readonly property bool running: winAddress !== ""
  readonly property bool hidden: running && winWorkspace.indexOf("special:") === 0

  // Forces a count so the badge can be looked at on demand. Otherwise the only
  // way to see it is to wait for somebody to message you, which is how it went
  // unverified for so long. `omarchy bar set fvargas.teams debugUnread 3`.
  readonly property int debugUnread: Math.max(0, Number(setting("debugUnread", 0)))

  // Teams puts the unread count at the head of the title: "(3) Chat | ..."
  readonly property int unread: {
    if (root.debugUnread > 0) return root.debugUnread
    var m = /^\((\d+)\)/.exec(root.winTitle)
    return m ? parseInt(m[1], 10) : 0
  }

  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property bool focused: {
    var t = root.activeToplevel
    if (!t) return false
    return String(t.appId || "").toLowerCase().indexOf(root.matchClass) >= 0
  }

  // ---- microphone / call detection ----
  readonly property var micSource: Pipewire.defaultAudioSource
  readonly property bool micMuted: micSource && micSource.audio ? micSource.audio.muted : false
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  // Which process a capture stream must belong to before it counts as a call.
  // Teams runs inside Chromium, and Chromium keeps its audio in a *separate*
  // process from the window, so the window PID is useless for matching --
  // the binary name is the only reliable signal.
  readonly property string micApp: String(setting("micApp", "chromium")).toLowerCase()

  // Every live capture stream, tracked so their `properties` maps stay populated.
  readonly property var captureStreams: {
    var out = []
    for (var i = 0; i < root.pwNodes.length; i++) {
      var n = root.pwNodes[i]
      if (n && n.isStream && n.isSink === false) out.push(n)
    }
    return out
  }

  PwObjectTracker { objects: root.captureStreams }

  // A capture stream belonging to Teams' browser means a call is in progress.
  // Filtering by process matters: without it *any* app touching the microphone
  // (a recorder, Zoom, OBS) would flip the widget into "in a call" and force
  // do-not-disturb on. Mute state is deliberately ignored -- muted-in-a-meeting
  // is still in a meeting.
  readonly property bool inCall: {
    if (!root.running) return false
    for (var i = 0; i < root.captureStreams.length; i++) {
      var props = root.captureStreams[i].properties || {}
      var who = String(props["application.process.binary"]
                       || props["application.name"] || "").toLowerCase()
      if (who.indexOf(root.micApp) >= 0) return true
    }
    return false
  }

  PwObjectTracker { objects: root.micSource ? [root.micSource] : [] }

  // ---- automatic do-not-disturb ----
  // Looking the notification service up by a fixed id is a trap. Cloning the
  // stock plugin gives the clone a new id and *disables* the original, so
  // "omarchy.notifications" then resolves to null and auto-DND silently does
  // nothing -- no error, no dot, just no DND. Find the service by the
  // capability we actually need instead, and let a setting force one id.
  readonly property string notificationsPlugin: String(setting("notificationsPlugin", ""))

  function findNotifications() {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.serviceFor !== "function") return null

    if (root.notificationsPlugin !== "")
      return shell.serviceFor(root.notificationsPlugin)

    var registry = shell.pluginRegistry
    var plugins = registry ? registry.installedPlugins : null
    if (!plugins) return null
    for (var id in plugins) {
      var svc = shell.serviceFor(id)
      if (svc && typeof svc.setDoNotDisturb === "function") return svc
    }
    return null
  }

  property bool dndHeldByUs: false
  property bool dndWasOn: false

  onInCallChanged: {
    if (!root.autoDnd) return
    // Resolved per transition rather than cached: services come and go as
    // plugins are enabled, and a null captured at startup would be permanent.
    var notifications = root.findNotifications()
    if (!notifications) return

    if (root.inCall) {
      if (root.dndHeldByUs) return
      root.dndWasOn = notifications.doNotDisturb === true
      root.dndHeldByUs = true
      if (!root.dndWasOn) notifications.setDoNotDisturb(true)
    } else if (root.dndHeldByUs) {
      root.dndHeldByUs = false
      // Only undo what we did; a DND the user turned on themselves stays on.
      if (!root.dndWasOn) notifications.setDoNotDisturb(false)
    }
  }

  // ---- actions ----
  // Omarchy 4 drives Hyprland through its Lua dispatch API. The pre-Lua form
  // ("dispatch movetoworkspacesilent ws,address:0x...") is rejected outright,
  // so every dispatch below is built as a Lua expression. The Lua uses double
  // quotes, so the shell side is wrapped in single quotes.
  function dispatchLua(lua) {
    return "hyprctl dispatch '" + lua + "'"
  }

  function moveLua(workspace) {
    return "hl.dsp.window.move({ window = \"address:" + root.winAddress
         + "\", workspace = \"" + workspace + "\", follow = false })"
  }

  function showApp() {
    if (!root.running) {
      root.bar.run("omarchy-launch-or-focus-webapp " + root.matchClass + " " + root.appUrl)
      probeSoon()
      return
    }
    var target = root.homeWorkspace !== ""
               ? root.homeWorkspace
               : String(Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1)

    var cmds = [root.dispatchLua(root.moveLua(target))]
    // Sending it to a fixed workspace is pointless if the eye stays elsewhere,
    // so follow it over before focusing the window itself.
    if (root.homeWorkspace !== "")
      cmds.push(root.dispatchLua("hl.dsp.focus({ workspace = \"" + target + "\" })"))
    cmds.push(root.dispatchLua("hl.dsp.focus({ window = \"address:" + root.winAddress + "\" })"))

    root.bar.run(cmds.join(" ; "))
    probeSoon()
  }

  // Actually quit Teams, as opposed to parking it. This is the only way out
  // now that SUPER+W hides instead of closing, so it lives on right-click.
  //
  // The address guard is not paranoia: hl.dsp.window.close() falls back to the
  // *active* window when handed an empty address, so an unset winAddress would
  // close whatever the user happens to be looking at.
  function quitApp() {
    if (!root.running || root.winAddress === "") return
    root.bar.run(root.dispatchLua(
      "hl.dsp.window.close({ window = \"address:" + root.winAddress + "\" })"))
    probeSoon()
  }

  function hideApp() {
    if (!root.running || root.hidden) return
    root.bar.run(root.dispatchLua(root.moveLua(root.hideWorkspace)))
    probeSoon()
  }

  // Dock behaviour: bring it to the front, or tuck it away if it is already there.
  function toggleApp() {
    if (!root.running || root.hidden) showApp()
    else if (root.focused) hideApp()
    else showApp()
  }

  function toggleMic() {
    if (root.micSource && root.micSource.audio)
      root.micSource.audio.muted = !root.micSource.audio.muted
  }

  function probeSoon() { settleTimer.restart() }

  // ---- window probe ----
  function applyClients(raw) {
    var addr = "", title = "", ws = ""
    try {
      var list = JSON.parse(raw)
      for (var i = 0; i < list.length; i++) {
        var c = list[i]
        if (String(c.class || "").toLowerCase().indexOf(root.matchClass) >= 0) {
          addr = String(c.address || "")
          title = String(c.title || "")
          ws = c.workspace ? String(c.workspace.name || "") : ""
          break
        }
      }
    } catch (e) {
      return // keep the last good reading rather than flapping the UI
    }
    root.winAddress = addr
    root.winTitle = title
    root.winWorkspace = ws
  }

  Process {
    id: probe
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.applyClients(String(text || ""))
    }
  }

  function refresh() { if (!probe.running) probe.running = true }

  Timer {
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: settleTimer
    interval: 250
    repeat: false
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "fvargas.teams"
    function toggle(): void { root.broadcast("toggleApp") }
    function show(): void { root.broadcast("showApp") }
    function hide(): void { root.broadcast("hideApp") }
    function quit(): void { root.broadcast("quitApp") }
    function menu(): void { root.toggle() }
    function refresh(): void { root.broadcast("refresh") }
  }

  // ---- presentation ----
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF02BB) // nf-md-microsoft_teams
    // Reserve the accent tint for a live call; "running" is already carried
    // by the presence dot, the way a macOS Dock tile does it.
    active: root.inCall
    opacity: root.running ? 1.0 : 0.45
    tooltipText: {
      if (!root.running) return "Teams — not running (click to open)"
      var bits = []
      bits.push(root.hidden ? "Teams — hidden" : "Teams")
      if (root.unread > 0) bits.push(root.unread + " unread")
      if (root.inCall) bits.push(root.micMuted ? "in a call (mic muted)" : "in a call")
      return bits.join(" · ")
    }
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleMic()
      else if (b === Qt.RightButton) root.toggle()
      else root.toggleApp()
    }

    Behavior on opacity {
      NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
  }

  // ---- the menu ----
  // Anchored to the icon and opened on right-click. Everything destructive or
  // non-obvious lives here rather than on a mouse button nobody would guess.
  readonly property string stateLine: {
    if (!root.running) return "Not running"
    var bits = [root.hidden ? "Hidden" : "Visible"]
    if (root.unread > 0) bits.push(root.unread + " unread")
    if (root.inCall) bits.push(root.micMuted ? "in a call · mic muted" : "in a call")
    return bits.join(" · ")
  }

  KeyboardPanel {
    id: menuPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: menuKeys
    contentWidth: menuPanel.fittedContentWidth(Style.space(260))
    contentHeight: menuPanel.fittedContentHeight(menuColumn.implicitHeight)

    PanelKeyCatcher {
      id: menuKeys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = String(t).toLowerCase()
        if (k === "h") { root.toggleApp(); root.close() }
        else if (k === "m") root.toggleMic()
        else if (k === "q") { root.quitApp(); root.close() }
      }

      Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // Header: what Teams is doing right now.
        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            text: "Microsoft Teams"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            text: root.stateLine
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.55)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        PanelSeparator { width: parent.width }

        Button {
          width: parent.width
          leftAlign: true
          bordered: true
          enabled: root.running
          iconText: root.hidden ? String.fromCodePoint(0xF06D0) : String.fromCodePoint(0xF06D1)
          text: root.hidden ? "Show Teams" : "Hide Teams"
          fontSize: Style.font.bodySmall
          foreground: root.bar ? root.bar.foreground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: { root.toggleApp(); root.close() }
        }

        Button {
          width: parent.width
          leftAlign: true
          bordered: true
          enabled: root.micSource !== null
          iconText: root.micMuted ? String.fromCodePoint(0xF036D) : String.fromCodePoint(0xF036C)
          text: root.micMuted ? "Unmute microphone" : "Mute microphone"
          fontSize: Style.font.bodySmall
          foreground: root.bar ? root.bar.foreground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          // Deliberately leaves the menu open: muting mid-call is something you
          // want to see confirmed, and the label flips in place.
          onClicked: root.toggleMic()
        }

        PanelSeparator { width: parent.width }

        Button {
          width: parent.width
          leftAlign: true
          bordered: true
          enabled: root.running
          iconText: String.fromCodePoint(0xF0206)
          text: "Quit Teams"
          fontSize: Style.font.bodySmall
          // Urgent, because this one actually kills the app rather than parking it.
          foreground: Color.urgent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: { root.quitApp(); root.close() }
        }
      }
    }
  }

  // Unread badge, in the top-right corner like a Dock tile.
  //
  // Sized against Style.bar.iconSlot (27px by default), not picked by eye: at
  // the original Style.space(13) the badge was half the slot and swallowed the
  // glyph it was supposed to annotate. A Dock badge sits at roughly a third of
  // the tile, and the ring in background colour is what keeps it legible where
  // it does overlap.
  Rectangle {
    id: badge
    visible: root.unread > 0
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: 0
    anchors.topMargin: Style.space(1)
    height: Math.round(Style.bar.iconSlot * 0.37)
    width: Math.max(height, badgeLabel.implicitWidth + Style.space(5))
    radius: height / 2
    color: Color.urgent
    border.width: 1
    border.color: Color.background
    z: 2

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      color: Color.background
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.max(7, Style.font.caption - 3)
      font.bold: true
    }
  }

  // Presence dot: accent when available, urgent while in a call.
  //
  // Colour alone cannot carry that distinction. Plenty of Omarchy themes make
  // accent and urgent near-identical -- the one this was built against resolves
  // them to #b59790 and #c38b7b, two dusty roses that are the same dot at 7px.
  // So the call state also grows and pulses, channels no palette can flatten.
  Rectangle {
    id: presenceDot
    visible: root.running && !root.hidden
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Style.space(2)
    anchors.bottomMargin: Style.space(3)
    width: root.inCall ? Style.space(10) : Style.space(7)
    height: width
    radius: width / 2
    color: root.inCall ? Color.urgent : Color.accent
    border.width: 1
    border.color: Color.background
    z: 2

    Behavior on width {
      NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    SequentialAnimation on opacity {
      running: root.inCall
      loops: Animation.Infinite
      // The animation owns `opacity` only while it runs; on stop it leaves the
      // dot wherever the cycle happened to be, so put it back to full.
      onRunningChanged: if (!running) presenceDot.opacity = 1.0
      NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }
  }
}
