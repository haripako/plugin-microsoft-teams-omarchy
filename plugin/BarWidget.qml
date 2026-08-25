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
BarWidget {
  id: root
  moduleName: "fvargas.teams"

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

  // Teams puts the unread count at the head of the title: "(3) Chat | ..."
  readonly property int unread: {
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

  // A live capture stream while Teams is open means a call is in progress.
  // Mute state is deliberately ignored: muted-in-a-meeting is still in a meeting.
  readonly property bool inCall: {
    if (!root.running) return false
    for (var i = 0; i < root.pwNodes.length; i++) {
      var n = root.pwNodes[i]
      if (n && n.isStream && n.isSink === false) return true
    }
    return false
  }

  PwObjectTracker { objects: root.micSource ? [root.micSource] : [] }

  // ---- automatic do-not-disturb ----
  readonly property var notifications: (bar && bar.shell && typeof bar.shell.firstPartyServiceFor === "function")
                                       ? bar.shell.firstPartyServiceFor("omarchy.notifications")
                                       : null
  property bool dndHeldByUs: false
  property bool dndWasOn: false

  onInCallChanged: {
    if (!root.autoDnd || !root.notifications) return

    if (root.inCall) {
      if (root.dndHeldByUs) return
      root.dndWasOn = root.notifications.doNotDisturb === true
      root.dndHeldByUs = true
      if (!root.dndWasOn) root.notifications.setDoNotDisturb(true)
    } else if (root.dndHeldByUs) {
      root.dndHeldByUs = false
      // Only undo what we did; a DND the user turned on themselves stays on.
      if (!root.dndWasOn) root.notifications.setDoNotDisturb(false)
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
      else if (b === Qt.RightButton) root.hideApp()
      else root.toggleApp()
    }

    Behavior on opacity {
      NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
  }

  // Unread badge, in the top-right corner like a Dock tile.
  Rectangle {
    id: badge
    visible: root.unread > 0
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Style.space(1)
    anchors.topMargin: Style.space(2)
    height: Style.space(13)
    width: Math.max(height, badgeLabel.implicitWidth + Style.space(6))
    radius: height / 2
    color: Color.urgent
    z: 2

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      color: Color.background
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.max(8, Style.font.caption - 2)
      font.bold: true
    }
  }

  // Presence dot: accent when available, urgent while in a call.
  Rectangle {
    id: presenceDot
    visible: root.running && !root.hidden
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Style.space(2)
    anchors.bottomMargin: Style.space(3)
    width: Style.space(7)
    height: width
    radius: width / 2
    color: root.inCall ? Color.urgent : Color.accent
    border.width: 1
    border.color: Color.background
    z: 2
  }
}
