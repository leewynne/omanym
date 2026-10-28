import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The hexagon bot in the bar, with the Bot of the Day's name beside it if
// set. Left click opens the popup, middle click copies the day's name, right
// click opens the day's bot on namemyai.org.
BarWidget {
  id: root
  moduleName: "leewynne.omanym"

  readonly property var omanym: panelLoader.item
  readonly property string label: omanym ? omanym.label : ""
  readonly property bool showLabel: !vertical && label !== ""

  // Shape contract for shell.summon/hide/toggle routing: Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root.
  readonly property bool opened: omanym ? omanym.opened === true : false

  function open() {
    if (omanym) omanym.open()
  }

  function close() {
    if (omanym) omanym.close()
  }

  function togglePanel() {
    if (omanym) omanym.toggle()
  }

  function refresh() {
    if (omanym) omanym.refresh()
  }

  function another() {
    if (!omanym) return
    if (!omanym.opened) omanym.open()
    omanym.another()
  }

  function copyToday() {
    if (omanym) omanym.copyName(omanym.dailyBot)
  }

  function search(q) {
    if (omanym) omanym.openSearch(q)
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: omanym ? omanym.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (omanym) omanym.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // The open-panel mark spans the name, like the clock's; the bot alone
  // leaves the bar to size it.
  readonly property real openPanelIndicatorWidth: showLabel ? pill.width : 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "leewynne.omanym"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function another(): void { root.another() }
    function copy(): void { root.copyToday() }
    function search(q: string): void { root.search(q) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : (root.showLabel ? pill.width + Style.space(7) : Math.max(Style.bar.iconSlot, pill.width))
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    dimmed: root.omanym ? root.omanym.dailyBot === null : true
    tooltipText: root.omanym ? root.omanym.tooltip : "Omanym"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.copyToday()
      else if (b === Qt.RightButton) { if (root.omanym) root.omanym.openBot(root.omanym.dailyBot) }
      else root.togglePanel()
    }

    Item {
      id: pill
      anchors.centerIn: parent
      width: pillRow.implicitWidth + (root.showLabel ? Style.space(10) : 0)
      height: pillRow.implicitHeight

      Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: Style.space(5)

        Bot {
          anchors.verticalCenter: parent.verticalCenter
          size: Math.round(Style.bar.iconFont * 1.45)
          ink: button.foreground
          animate: root.omanym ? root.omanym.animate : false
          strokeUnits: 15
          eyeUnits: 22
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          visible: root.showLabel
          text: root.label
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
