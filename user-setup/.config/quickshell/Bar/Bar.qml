import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import ".."

PanelWindow {
  id: barWindow
  property var modelData
  property alias isVisible: barWindow.visible
  screen: modelData

  visible: EventBus.barVisible

  anchors {
    top: true
    left: true
    right: true
  }

  implicitHeight: Settings.barHeight
  color: Colors.transparent

  margins {
    top: Settings.marginSmall
    bottom: 0
    left: Settings.marginSmall
    right: Settings.marginSmall
  }

  Rectangle {
    anchors.fill: parent
    color: Colors.transparent

    RowLayout {
      anchors.fill: parent
      spacing: 0

      BarLeft {}
      BarCenter {}
      BarRight {}
    }
  }
}
