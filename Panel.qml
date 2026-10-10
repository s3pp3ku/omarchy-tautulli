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

  // ---------------------------------------------------------------- settings

  // The URL and API key are credentials, not preferences, so they live in
  // their own local-only file under ~/.local/state rather than in this
  // widget's shell.json/extra-bars.json entry — those two files get swept
  // into the user's dotfiles backup and pushed to GitHub on every change.
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/"
  readonly property string credentialsPath: stateDir + "tautulli-credentials.json"

  property string tautulliUrl: ""
  property string apiKey: ""
  property bool credentialsLoaded: false

  readonly property int pollSeconds: Math.max(10, parseInt(setting("pollSeconds", 30), 10) || 30)
  readonly property bool dimWhenIdle: setting("dimWhenIdle", true) === true
  readonly property bool showPosters: setting("showPosters", true) === true
  readonly property bool configured: tautulliUrl !== "" && apiKey !== ""

  // pms_image_proxy only honors the API key through the /api/v2 command
  // form; the bare /pms_image_proxy path redirects to a login page even
  // with ?apikey= set.
  function posterUrl(session) {
    if (!root.showPosters || !session || session.posterPath === "") return ""
    return root.tautulliUrl + "/api/v2?apikey=" + encodeURIComponent(root.apiKey)
      + "&cmd=pms_image_proxy&img=" + encodeURIComponent(session.posterPath)
      + "&width=120&height=180"
  }

  property bool editingCredentials: false
  property string urlDraft: ""
  property string keyDraft: ""

  function startEditingCredentials() {
    urlDraft = tautulliUrl
    keyDraft = apiKey
    editingCredentials = true
    Qt.callLater(function() {
      urlField.text = root.urlDraft
      keyField.text = root.keyDraft
    })
  }

  function cancelEditingCredentials() {
    editingCredentials = false
  }

  // Strips a trailing slash and, since the single most common copy-paste
  // mistake is bookmarking Tautulli's own web UI instead of its base URL,
  // a trailing /home (or any of its other top-level UI routes) too. The
  // API always lives at <base>/api/v2 regardless of which page you copied
  // the address bar from.
  function cleanTautulliUrl(raw) {
    return String(raw || "").trim()
      .replace(/\/+$/, "")
      .replace(/\/(home|history|graphs|sync|logs|settings|status|update)\/?$/i, "")
      .replace(/\/+$/, "")
  }

  function saveCredentials() {
    var url = cleanTautulliUrl(urlDraft)
    var key = keyDraft.trim()
    tautulliUrl = url
    apiKey = key
    editingCredentials = false
    ensureStateDirProc.running = true
    credentialsFile.setText(JSON.stringify({ url: url, apiKey: key }, null, 2) + "\n")
    if (url !== "" && key !== "") root.refresh()
  }

  Process {
    id: ensureStateDirProc
    command: ["mkdir", "-p", root.stateDir]
  }

  FileView {
    id: credentialsFile
    path: root.credentialsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadCredentials(text())
    onLoadFailed: root.loadCredentials("")
  }

  function loadCredentials(raw) {
    if (root.credentialsLoaded) return
    try {
      var parsed = raw ? JSON.parse(raw) : {}
      var rawUrl = String(parsed.url || "")
      var cleanedUrl = root.cleanTautulliUrl(rawUrl)
      root.tautulliUrl = cleanedUrl
      root.apiKey = String(parsed.apiKey || "")
      // Rewrite a file saved before cleanTautulliUrl existed (or hand-edited
      // with a /home suffix) so it's fixed for good, not just this session.
      // Deferred: calling setText() from inside onLoaded's own call stack
      // doesn't stick.
      if (cleanedUrl !== rawUrl && cleanedUrl !== "") {
        var healedKey = root.apiKey
        Qt.callLater(function() {
          credentialsFile.setText(JSON.stringify({ url: cleanedUrl, apiKey: healedKey }, null, 2) + "\n")
        })
      }
    } catch (e) {
      root.tautulliUrl = ""
      root.apiKey = ""
    }
    root.credentialsLoaded = true
  }

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
  //
  // A raw MouseArea + PanelToolTip looked right in isolation but the real
  // bar runs its tooltips through bar.showTooltip()/hideTooltip() (one
  // shared surface, not a Popup per icon) and tracks click targets through
  // bar.registerClickTarget() for its own press/drag handling, both wired
  // up by WidgetButton/BarIconButton already. Hand-rolling it here is what
  // made the tooltip not show and clicks not open the popup reliably.

  implicitWidth: iconButton.implicitWidth
  implicitHeight: iconButton.implicitHeight

  BarIconButton {
    id: iconButton
    anchors.fill: parent
    bar: root.bar
    text: "\uf008"
    foreground: root.fg
    dimmed: root.configured && root.idle && root.dimWhenIdle
    tooltipText: !root.configured
      ? "Plex Activity \u2014 needs a Tautulli URL and API key"
      : (root.idle ? "Nobody's watching Plex" : root.streamCount + (root.streamCount === 1 ? " stream" : " streams") + " on Plex")
    onPressed: function(button) { root.toggle() }
  }

  // ------------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: iconButton
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(580))

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    // A Flickable, not a plain Column: fittedContentHeight already caps the
    // popup to fit the screen, but with ten sessions the content is taller
    // than that cap — without this it would just get clipped at the bottom
    // instead of scrolling.
    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight + Style.space(40)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        x: Style.space(20)
        y: Style.space(20)
        width: scroll.width - Style.space(40)
        spacing: Style.space(14)

      Row {
        id: headerRow
        width: parent.width
        spacing: Style.space(10)

        Column {
          width: parent.width - headerButtons.width - headerRow.spacing
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
            text: !root.credentialsLoaded
              ? "Loading..."
              : (root.configured
                ? (root.idle ? "Nobody's watching right now" : root.streamCount + (root.streamCount === 1 ? " stream" : " streams") + " active")
                : "Not set up yet — click SET UP")
            color: root.fg
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Row {
          id: headerButtons
          spacing: Style.space(6)
          Button {
            text: root.configured ? "EDIT" : "SET UP"
            tooltipText: root.configured ? "Change the Tautulli URL or API key" : "Enter your Tautulli URL and API key"
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            foreground: root.fg
            bordered: true
            onClicked: root.editingCredentials ? root.cancelEditingCredentials() : root.startEditingCredentials()
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
      }

      PanelSeparator { foreground: root.themeAccent }

      Column {
        width: parent.width
        spacing: Style.space(10)
        visible: root.editingCredentials

        Text {
          text: "TAUTULLI URL"
          color: root.fg
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
        TextField {
          id: urlField
          width: parent.width
          placeholderText: "http://192.168.1.50:8181"
          foreground: root.fg
          font.family: root.fontFamily
          onTextChanged: root.urlDraft = text
        }
        Text {
          text: "API KEY"
          color: root.fg
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
        TextField {
          id: keyField
          width: parent.width
          placeholderText: "from Tautulli → Settings → Web Interface → API"
          foreground: root.fg
          font.family: root.fontFamily
          onTextChanged: root.keyDraft = text
        }
        Text {
          width: parent.width
          text: "Stored only on this machine, in ~/.local/state/omarchy/ — never swept into a dotfiles backup."
          color: root.fg
          opacity: 0.5
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          spacing: Style.space(6)
          Button {
            text: "SAVE"
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            foreground: root.fg
            bordered: true
            enabled: root.urlDraft.trim() !== "" && root.keyDraft.trim() !== ""
            onClicked: root.saveCredentials()
          }
          Button {
            text: "CANCEL"
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            foreground: root.fg
            bordered: true
            onClicked: root.cancelEditingCredentials()
          }
        }
      }

      Text {
        visible: !root.editingCredentials && root.lastError !== ""
        width: parent.width
        text: root.lastError
        color: Color.urgent
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: !root.editingCredentials && root.configured && root.lastError === "" && root.idle
        text: "Everything's quiet on the server."
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: !root.editingCredentials && root.sessions.length > 0

        Repeater {
          model: root.sessions

          Rectangle {
            id: card
            required property var modelData
            width: column.width
            implicitHeight: Math.max(posterFrame.height, cardColumn.implicitHeight) + Style.space(30)
            radius: Style.cornerRadius
            color: Qt.alpha(root.themeAccent, 0.10)
            border.width: 1
            border.color: Qt.alpha(root.themeAccent, 0.45)

            Rectangle {
              width: Style.space(3)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              radius: width / 2
              color: root.themeAccent
            }

            Rectangle {
              id: posterFrame
              visible: poster.source !== ""
              width: visible ? Style.space(62) : 0
              height: Style.space(93)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.cornerRadius
              clip: true
              color: Qt.alpha(root.fg, 0.08)

              Image {
                id: poster
                anchors.fill: parent
                source: root.posterUrl(card.modelData)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
              }
            }

            Column {
              id: cardColumn
              anchors.left: posterFrame.right
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              anchors.rightMargin: Style.space(16)
              spacing: Style.space(7)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: card.modelData.user
                  color: root.themeAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  color: Qt.alpha(root.themeAccent, 0.22)
                  implicitWidth: stateLabel.implicitWidth + Style.space(12)
                  implicitHeight: stateLabel.implicitHeight + Style.space(4)
                  Text {
                    id: stateLabel
                    anchors.centerIn: parent
                    text: card.modelData.state.toUpperCase()
                    color: root.themeAccent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }
                }
              }

              Text {
                width: parent.width
                text: [
                  card.modelData.episodeTag,
                  card.modelData.title + (card.modelData.year !== "" ? " (" + card.modelData.year + ")" : "")
                ].filter(function(v) { return v !== "" }).join("  \u2022  ")
                color: root.fg
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: card.modelData.library
                color: root.themeMuted
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                text: [card.modelData.player || card.modelData.product, card.modelData.quality]
                  .filter(function(v) { return v !== "" }).join("  \u2022  ")
                color: root.fg
                opacity: 0.7
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: [card.modelData.bandwidth, card.modelData.ipAddress]
                  .filter(function(v) { return v !== "" }).join("  \u2022  ")
                color: root.fg
                opacity: 0.55
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Rectangle {
                  id: track
                  width: parent.width - remainingLabel.implicitWidth - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(5)
                  radius: height / 2
                  color: Qt.alpha(root.themeAccent, 0.18)

                  Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * (card.modelData.progressPercent / 100)
                    color: root.themeAccent
                  }
                }

                Text {
                  id: remainingLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: card.modelData.remaining !== "" ? card.modelData.remaining : card.modelData.progressPercent + "%"
                  color: root.themeMuted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
      }
    }
  }
}