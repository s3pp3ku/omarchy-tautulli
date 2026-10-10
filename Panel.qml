import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Who's watching Plex right now, pulled from the user's own Tautulli
// instance. Tautulli already does the hard work (session tracking, quality
// decisions); this just polls get_activity and lays it out in the bar.
Panel {
  id: root
  moduleName: "s3pp3ku.tautulli"
  ipcTarget: "s3pp3ku.tautulli"
  manageIpc: false

  property var anchorItem: null

  // ---------------------------------------------------------------- settings

  readonly property string tautulliUrl: String(setting("url", "")).trim().replace(/\/+$/, "")
  readonly property string apiKey: String(setting("apiKey", "")).trim()
  readonly property int pollSeconds: Math.max(10, parseInt(setting("pollSeconds", 30), 10) || 30)
  readonly property bool showCount: setting("showCount", true) === true
  readonly property bool dimWhenIdle: setting("dimWhenIdle", true) === true
  readonly property bool configured: tautulliUrl !== "" && apiKey !== ""

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color themeAccent: Color.accent
  readonly property color themeMuted: Color.muted

  // -------------------------------------------------------------------- state

  property var sessions: []
  property int streamCount: 0
  property string lastError: ""
  property bool loading: false
  property double lastUpdatedAt: 0

  readonly property bool idle: streamCount <= 0

  function open() { root.controller.show(); root.refresh() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root, direction)
    return false
  }

  function refresh() {
    if (!configured || activityProc.running) return
    loading = true
    var url = root.tautulliUrl + "/api/v2?apikey=" + encodeURIComponent(root.apiKey) + "&cmd=get_activity"
    activityProc.command = ["curl", "-fsS", "--max-time", "8", url]
    activityProc.running = true
  }

  Process {
    id: activityProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        try {
          var result = Model.parseActivity(text)
          if (!result.ok) {
            root.lastError = result.error
            return
          }
          root.sessions = result.sessions
          root.streamCount = result.streamCount
          root.lastError = ""
          root.lastUpdatedAt = Date.now()
        } catch (e) {
          root.lastError = "Couldn't read Tautulli's response"
        }
      }
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.lastError === "") root.lastError = "Couldn't reach Tautulli at that URL"
    }
  }

  Timer {
    interval: root.pollSeconds * 1000
    running: root.configured
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // --------------------------------------------------------------- bar button

  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: ""
      color: !root.configured ? Qt.darker(root.fg, 1.6) : (root.idle && root.dimWhenIdle ? Qt.darker(root.fg, 1.4) : root.themeAccent)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: String(root.streamCount)
      visible: !root.vertical && root.showCount && root.configured && root.streamCount > 0
      color: root.themeAccent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  MouseArea {
    id: clickArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()

    PanelToolTip {
      visible: clickArea.containsMouse
      text: !root.configured
        ? "Plex Activity — needs a Tautulli URL and API key"
        : (root.idle ? "Nobody's watching Plex" : root.streamCount + (root.streamCount === 1 ? " stream" : " streams") + " on Plex")
    }
  }

  // ------------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Column {
      id: column
      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(14)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Column {
          width: parent.width - refreshButton.width - parent.spacing
          spacing: Style.space(3)
          Text {
            text: "PLEX ACTIVITY"
            color: root.themeAccent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 1.5
          }
          Text {
            text: root.configured
              ? (root.idle ? "Nobody's watching right now" : root.streamCount + (root.streamCount === 1 ? " stream" : " streams") + " active")
              : "Set your Tautulli URL and API key in this widget's settings"
            color: root.fg
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Button {
          id: refreshButton
          text: root.loading ? "..." : "REFRESH"
          tooltipText: "Poll Tautulli again now"
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          foreground: root.fg
          bordered: true
          enabled: root.configured && !root.loading
          onClicked: root.refresh()
        }
      }

      PanelSeparator { foreground: root.themeAccent }

      Text {
        visible: root.lastError !== ""
        width: parent.width
        text: root.lastError
        color: Color.urgent
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: root.configured && root.lastError === "" && root.idle
        text: "Everything's quiet on the server."
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Column {
        width: parent.width
        spacing: Style.space(14)
        visible: root.sessions.length > 0

        Repeater {
          model: root.sessions

          Column {
            required property var modelData
            width: column.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: modelData.user
                color: root.themeAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                text: modelData.state.toUpperCase()
                color: root.fg
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
            }

            Text {
              width: parent.width
              text: modelData.title
              color: root.fg
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              text: [modelData.player, modelData.quality, modelData.location].filter(function(v) { return v !== "" }).join("  •  ")
              color: root.fg
              opacity: 0.6
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              width: parent.width
              height: Style.space(4)
              radius: height / 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

              Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * (modelData.progressPercent / 100)
                color: root.themeAccent
              }
            }
          }
        }
      }
    }
  }
}
