import QtQuick
import ".."

MouseArea {
  anchors.fill: parent
  acceptedButtons: Qt.NoButton
  scrollGestureEnabled: false
  z: 999

  property real stepSize: Settings.menuItemSize
  property bool horizontal: false

  onWheel: wheel => {
    const angle = horizontal ? wheel.angleDelta.x : wheel.angleDelta.y
    if (angle === 0) return
    const delta = angle / 120 * Settings.scrollSpeed * stepSize
    if (horizontal) {
      const max = Math.max(0, parent.contentWidth - parent.width)
      parent.contentX = Math.max(0, Math.min(max, parent.contentX - delta))
    } else {
      const max = Math.max(0, parent.contentHeight - parent.height)
      parent.contentY = Math.max(0, Math.min(max, parent.contentY - delta))
    }
  }
}
