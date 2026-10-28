import QtQuick
import QtQuick.Shapes

// The namemyai.org mascot: a hexagon head whose eyes glance about and blink,
// drawn in the theme's colours. Coordinates are the site's SVG (a 200 unit
// square), scaled to size. The bar's copy is bolder so it reads at icon size.
Item {
  id: root

  property real size: 24
  property color ink: "white"
  property color face: "transparent"
  property bool animate: true
  // The head tilts with its gaze, and a highlight sweeps the brow; for the
  // popup, where it's big enough to see.
  property bool tilt: false
  // Outline and eye width, in the 200 unit square.
  property real strokeUnits: 9
  property real eyeUnits: 16

  // Gaze in [-1, 1], 0 looking straight out.
  property real lookX: 0
  property real lookY: 0
  property real blink: 0
  property real joy: 0

  readonly property real u: size / 200

  implicitWidth: size
  implicitHeight: size

  Behavior on lookX { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
  Behavior on lookY { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

  // Look somewhere for a while before the eyes wander off again.
  function lookAt(x, y) {
    lookX = Math.max(-1, Math.min(1, x))
    lookY = Math.max(-1, Math.min(1, y))
    if (animate) glanceTimer.restart()
  }

  // The site's happy squint, for a copied name.
  function happy() {
    if (!animate) return
    joyAnimation.restart()
  }

  onAnimateChanged: {
    if (!animate) {
      lookX = 0
      lookY = 0
      blink = 0
      joy = 0
    }
  }

  SequentialAnimation {
    id: blinkAnimation
    NumberAnimation { target: root; property: "blink"; to: 1; duration: 80; easing.type: Easing.InQuad }
    NumberAnimation { target: root; property: "blink"; to: 0; duration: 80; easing.type: Easing.OutQuad }
  }

  SequentialAnimation {
    id: joyAnimation
    NumberAnimation { target: root; property: "joy"; to: 1; duration: 160; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 720 }
    NumberAnimation { target: root; property: "joy"; to: 0; duration: 220; easing.type: Easing.InQuad }
  }

  // A blink every few seconds, now and then a double one.
  Timer {
    id: blinkTimer
    interval: 3000
    running: root.animate && root.visible
    onTriggered: {
      blinkAnimation.restart()
      if (Math.random() < 0.2) doubleBlink.restart()
      interval = 2200 + Math.random() * 4200
      restart()
    }
  }

  Timer {
    id: doubleBlink
    interval: 260
    onTriggered: blinkAnimation.restart()
  }

  // Idle glances, back to the middle about half the time.
  Timer {
    id: glanceTimer
    interval: 4000
    running: root.animate && root.visible
    onTriggered: {
      if (Math.random() < 0.45) {
        root.lookX = 0
        root.lookY = 0
      } else {
        root.lookX = Math.random() * 1.6 - 0.8
        root.lookY = Math.random() * 0.9 - 0.5
      }
      interval = 2500 + Math.random() * 4500
      restart()
    }
  }

  Item {
    id: head
    width: root.size
    height: root.size

    transform: [
      Rotation {
        origin.x: 100 * root.u
        origin.y: 104 * root.u
        angle: root.tilt ? root.lookX * 7 : 0
      },
      Translate {
        x: root.tilt ? root.lookX * 7 * root.u : 0
        y: root.tilt ? root.lookY * 6 * root.u : 0
      }
    ]

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4

      ShapePath {
        strokeColor: root.ink
        strokeWidth: Math.max(1, root.strokeUnits * root.u)
        fillColor: root.face
        joinStyle: ShapePath.RoundJoin
        startX: 100 * root.u
        startY: 22 * root.u
        PathLine { x: 166 * root.u; y: 58 * root.u }
        PathLine { x: 166 * root.u; y: 142 * root.u }
        PathLine { x: 100 * root.u; y: 178 * root.u }
        PathLine { x: 34 * root.u; y: 142 * root.u }
        PathLine { x: 34 * root.u; y: 58 * root.u }
        PathLine { x: 100 * root.u; y: 22 * root.u }
      }

      ShapePath {
        strokeColor: root.tilt ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14) : "transparent"
        strokeWidth: 7 * root.u
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: 58 * root.u
        startY: 66 * root.u
        PathQuad { x: 142 * root.u; y: 66 * root.u; controlX: 100 * root.u; controlY: 40 * root.u }
      }
    }

    Item {
      id: eyes
      anchors.fill: parent

      transform: [
        Scale {
          origin.x: 100 * root.u
          origin.y: 98 * root.u
          yScale: Math.max(0.08, (1 - root.blink) * (1 - root.joy * 0.62))
        },
        Translate {
          x: root.lookX * 17 * root.u
          y: (root.lookY * 13 - root.joy * 6) * root.u
        }
      ]

      Repeater {
        model: [80, 120]

        Rectangle {
          required property real modelData
          x: (modelData - root.eyeUnits / 2) * root.u
          y: 76 * root.u
          width: root.eyeUnits * root.u
          height: 44 * root.u
          radius: width / 2
          rotation: -14
          antialiasing: true
          color: root.ink
        }
      }
    }
  }
}
