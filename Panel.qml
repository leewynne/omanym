import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Bot of the Day and the name finder. sync.sh keeps a copy of
// namemyai.org's data in ~/.cache/omanym and hands it over; the cached copy
// loads first so the bar has a bot straight away, then the site is checked
// for anything newer. c copies the name, a shows another, t goes back to
// today's, o opens it on namemyai.org, / searches by job.
Panel {
  id: root
  moduleName: "leewynne.omanym"
  manageIpc: false

  property var anchorItem: null

  // The bar identifies an open panel by the widget in its slot, so the
  // popout coordinator and Tab switching have to see BarWidget.qml, not this.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string labelStyle: Model.labelStyle(String(setting("label", "icon")))
  readonly property bool animate: Model.switchedOn(setting("animate", true))

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omanym"
  readonly property string syncScript: decodeURIComponent(String(Qt.resolvedUrl("sync.sh")).replace(/^file:\/\//, ""))

  // The site's data (Model.parseData), null until the first load.
  property var names: null
  property bool syncing: syncProc.running
  property bool pendingCheck: false
  property bool offline: false

  property string today: Model.dayKey(new Date())
  readonly property var pool: names ? Model.botPool(names.characters) : []
  readonly property var dailyBot: Model.botOfDay(pool, today)
  // Set by Another; null shows the day's bot.
  property var shownBot: null
  readonly property var bot: shownBot || dailyBot

  property string query: ""
  readonly property var suggestion: Model.suggest(names, query)
  readonly property var results: suggestion.list
  readonly property var selfNames: names && query.trim() !== "" ? Model.selfPick(names.selfnames, query) : []
  property int selected: 0

  // What was copied last, for the tick: a character's slug or "self:" + name.
  property string copied: ""

  readonly property string label: labelStyle === "name" && dailyBot ? Model.shortName(dailyBot.name) : ""
  readonly property string tooltip: dailyBot
    ? "Bot of the Day: " + dailyBot.name + "\n" + Model.sourceLine(dailyBot) + "\n\nMiddle-click to copy the name"
    : (syncing ? "Omanym: fetching names from namemyai.org…" : "Omanym: couldn't reach namemyai.org")

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(barForeground, 1.4)

  onQueryChanged: {
    selected = 0
    resultScroll.contentY = 0
  }

  // Opens on the day's bot, keeping whatever was searched for last.
  function open() {
    shownBot = null
    today = Model.dayKey(new Date())
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function openSearch(q) {
    if (!root.opened) open()
    searchField.text = q || ""
    Qt.callLater(searchField.forceActiveFocus)
  }

  function another() {
    var next = Model.another(pool, bot, Math.random())
    if (next) shownBot = next
  }

  function backToToday() {
    shownBot = null
  }

  function copyText(text, key, note) {
    if (!text) return
    Quickshell.execDetached(["wl-copy", "--", text])
    copied = key
    copiedTimer.restart()
    heroBot.happy()
    // Copied from the bar with the popup shut: say so.
    if (!root.opened) Quickshell.execDetached(["notify-send", "-a", "Omanym", "-t", "3000", "Copied " + text, note || ""])
  }

  function copyName(c) {
    if (c) copyText(Model.shortName(c.name), c.slug, "From " + c.sourceTitle)
  }

  function openUrl(url) {
    Quickshell.execDetached(["omarchy-launch-browser", url])
    root.close()
  }

  function openBot(c) {
    if (c) openUrl(Model.characterUrl(c))
  }

  function moveSelection(delta) {
    if (results.length === 0) return
    selected = Math.max(0, Math.min(results.length - 1, selected + delta))
    var row = resultRepeater.itemAt(selected)
    if (!row) return
    var top = row.y + resultColumn.y
    var bottom = top + row.height
    if (top < resultScroll.contentY) resultScroll.contentY = top
    else if (bottom > resultScroll.contentY + resultScroll.height) resultScroll.contentY = bottom - resultScroll.height
  }

  function scroll(direction) {
    var max = Math.max(0, resultScroll.contentHeight - resultScroll.height)
    resultScroll.contentY = Math.max(0, Math.min(max, resultScroll.contentY + direction * Style.space(48)))
  }

  // Cached copy first unless asked to go online; a check asked for while
  // one is running follows it.
  function sync(online) {
    if (syncProc.running) {
      if (online) pendingCheck = true
      return
    }
    syncProc.online = online
    syncProc.command = ["bash", syncScript, cacheDir].concat(online ? [] : ["--cached"])
    syncProc.running = true
  }

  function refresh() {
    sync(true)
  }

  function load(text) {
    var parsed = Model.parseData(text)
    if (!parsed) return
    if (names && names.version === parsed.version) return
    names = parsed
  }

  function emptyText() {
    if (!names) return syncing ? "Fetching names from namemyai.org…" : "Couldn't reach namemyai.org. Press r to try again."
    if (query.trim() !== "" && results.length === 0) return "No characters match “" + query.trim() + "”. Try a job like coding, research or travel."
    return ""
  }

  Component.onCompleted: {
    pendingCheck = true
    sync(false)
  }

  Process {
    id: syncProc
    property bool online: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.load(String(text || ""))
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!syncProc.online) return
        root.offline = String(text || "").indexOf("couldn't update") >= 0
        if (root.offline) retryTimer.restart()
        else retryTimer.stop()
      }
    }

    onExited: {
      if (!root.pendingCheck) return
      root.pendingCheck = false
      Qt.callLater(function() { root.sync(true) })
    }
  }

  // Checking costs one small request for the site's home page; the data
  // itself only comes down when the site has changed.
  Timer {
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.sync(true)
  }

  // Offline, after a boot before the network is up say: try again soon
  // rather than waiting out the six hours.
  Timer {
    id: retryTimer
    interval: 5 * 60 * 1000
    onTriggered: root.sync(true)
  }

  // A new day brings a new bot.
  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.today = Model.dayKey(new Date())
  }

  Timer {
    id: copiedTimer
    interval: 1600
    onTriggered: root.copied = ""
  }

  component Caption: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : 0
    wrapMode: Text.WordWrap
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    visible: text !== ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(header.implicitHeight + resultColumn.implicitHeight + footer.implicitHeight + Style.space(24), Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The search field owns the keys while it's focused.
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx > 0) root.another()
        else if (dx < 0) root.backToToday()
        else root.scroll(dy)
      }
      onActivateRequested: root.copyName(root.bot)
      onTextKey: function(t) {
        if (t === "c") root.copyName(root.bot)
        else if (t === "a" || t === "n") root.another()
        else if (t === "t") root.backToToday()
        else if (t === "o") root.openBot(root.bot)
        else if (t === "r") root.refresh()
        else if (t === "/" || t === "s") searchField.forceActiveFocus()
      }

      Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        // The bot: the mascot, then who it is and where it's from.
        Item {
          width: parent.width
          height: Math.max(heroBot.height, heroText.implicitHeight)

          Bot {
            id: heroBot
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            size: Style.space(64)
            ink: Color.accent
            face: Util.alpha(Color.accent, 0.08)
            animate: root.animate && root.opened
            tilt: true
          }

          Column {
            id: heroText
            anchors.left: heroBot.right
            anchors.right: parent.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              text: (root.shownBot ? "Another bot" : "Bot of the Day · " + Qt.formatDate(new Date(), "ddd d MMM")).toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              text: root.bot ? root.bot.name : (root.syncing ? "Fetching names…" : "Offline")
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              visible: text !== ""
              text: Model.sourceLine(root.bot)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WordWrap
          visible: text !== ""
          text: root.bot ? root.bot.overview : root.emptyText()
          color: root.bot ? root.barForeground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Row {
          spacing: Style.space(6)
          visible: root.bot !== null

          Button {
            iconText: root.bot && root.copied === root.bot.slug ? Model.glyphs.check : Model.glyphs.copy
            text: root.bot && root.copied === root.bot.slug ? "Copied" : "Copy name"
            tooltipText: "Copy " + (root.bot ? Model.shortName(root.bot.name) : "the name") + " (c)"
            foreground: root.barForeground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.copyName(root.bot)
          }

          Button {
            iconText: Model.glyphs.shuffle
            text: "Another"
            tooltipText: "Show another bot (a)"
            foreground: root.barForeground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.another()
          }

          Button {
            visible: root.shownBot !== null
            iconText: Model.glyphs.today
            text: "Today's"
            tooltipText: "Back to the Bot of the Day (t)"
            foreground: root.barForeground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.backToToday()
          }

          Button {
            iconText: Model.glyphs.open
            tooltipText: "Open on namemyai.org (o)"
            foreground: root.barForeground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.openBot(root.bot)
          }
        }

        PanelSeparator {
          foreground: root.barForeground
        }

        TextField {
          id: searchField
          width: parent.width
          enabled: root.names !== null
          placeholderText: "What will your bot do? Coding, research, travel…"
          foreground: root.barForeground
          font.family: root.fontFamily
          onTextChanged: root.query = text

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Down) {
              root.moveSelection(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveSelection(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              var pick = root.results[root.selected]
              if (event.modifiers & Qt.ControlModifier) root.openBot(pick)
              else root.copyName(pick)
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              if (text !== "") text = ""
              else root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
          }
        }

        Caption {
          text: root.suggestion.role ? "Best for " + root.suggestion.role.label + " · Enter copies" : ""
        }
      }

      Flickable {
        id: resultScroll
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(6)
        anchors.bottomMargin: Style.space(8)
        contentWidth: width
        contentHeight: resultColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: resultColumn
          width: resultScroll.width
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(6)
            wrapMode: Text.WordWrap
            visible: text !== "" && root.names !== null
            text: root.emptyText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            id: resultRepeater
            model: root.results

            // A suggestion: click copies the name, right click or the
            // arrow opens it on namemyai.org.
            Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool current: index === root.selected
              readonly property bool done: root.copied === modelData.slug

              width: resultColumn.width
              height: rowText.implicitHeight + Style.space(10)
              radius: Style.cornerRadius
              color: current || rowMouse.containsMouse ? Util.alpha(root.barForeground, 0.08) : "transparent"

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selected = row.index
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) root.openBot(row.modelData)
                  else root.copyName(row.modelData)
                }
              }

              Column {
                id: rowText
                anchors.left: parent.left
                anchors.right: rowOpen.left
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: (row.done ? Model.glyphs.check + " Copied " : "") + row.modelData.name
                  color: row.done ? Color.accent : root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: Model.sourceLine(row.modelData)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: row.modelData.overview
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              PanelActionButton {
                id: rowOpen
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: Model.glyphs.open
                tooltipText: "Open on namemyai.org"
                foreground: root.barForeground
                fontFamily: root.fontFamily
                onClicked: root.openBot(row.modelData)
              }
            }
          }

          // Names AIs chose for themselves, themed by the job, as the site
          // offers under its suggestions.
          Column {
            width: parent.width
            topPadding: Style.space(8)
            spacing: Style.space(6)
            visible: root.selfNames.length > 0

            PanelSectionHeader {
              width: parent.width
              text: "Or a name an AI chose for itself".toUpperCase()
              foreground: root.barForeground
              fontFamily: root.fontFamily
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.selfNames

                Button {
                  required property var modelData
                  readonly property bool done: root.copied === "self:" + modelData.name
                  iconText: done ? Model.glyphs.check : ""
                  text: modelData.name
                  tooltipText: modelData.meaning
                  foreground: root.barForeground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  bordered: true
                  onClicked: root.copyText(modelData.name, "self:" + modelData.name)
                }
              }
            }
          }
        }
      }

      Column {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(4)

        PanelSeparator {
          foreground: root.barForeground
        }

        Caption {
          text: "All characters and titles belong to their respective owners. Name My AI is a fan-made guide, not affiliated with any of them."
        }

        Item {
          width: parent.width
          height: Math.max(footerText.implicitHeight, footerActions.implicitHeight)

          Text {
            id: footerText
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: footerActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: (root.offline ? "Offline · " : "") + "namemyai.org"
              + (root.names ? " · " + root.names.characters.length + " characters" : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            id: footerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            PanelActionButton {
              iconText: Model.glyphs.refresh
              tooltipText: "Check namemyai.org for new names (r)"
              foreground: root.barForeground
              fontFamily: root.fontFamily
              enabled: !root.syncing
              onClicked: root.refresh()
            }

            PanelActionButton {
              iconText: Model.glyphs.search
              tooltipText: "Find names on namemyai.org"
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onClicked: root.openUrl(Model.suggestUrl(root.query))
            }
          }
        }
      }
    }
  }
}
