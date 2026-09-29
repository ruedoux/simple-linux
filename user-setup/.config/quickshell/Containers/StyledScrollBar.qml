import QtQuick
import QtQuick.Controls
import ".."

ScrollBar {
  policy: ScrollBar.AsNeeded
  implicitWidth: Settings.marginMedium
  implicitHeight: Settings.marginMedium

  background: Rectangle {
    radius: Math.min(width, height) / 2
    color: Colors.surface_container
  }

  contentItem: Rectangle {
    radius: Math.min(width, height) / 2
    color: Colors.primary
  }
}
