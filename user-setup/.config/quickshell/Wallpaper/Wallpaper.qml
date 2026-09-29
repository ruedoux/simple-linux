import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../Containers"

PanelWindow {
  property var modelData
  property alias isVisible: wallpaper.visible
  property int focusIndex: 0

  readonly property int visibleThumbnailCount: Math.min(
    WallpaperService.files.length,
    Settings.wallpaperThumbnailCount
  )
  readonly property int panelWidth: Math.min(
    Settings.wallpaperPanelWidth,
    (visibleThumbnailCount + 1) * Settings.wallpaperThumbnailSize
      + visibleThumbnailCount * Settings.marginMedium
      + Settings.marginMedium * 2
  )

  id: wallpaper
  screen: modelData
  color: Colors.transparent
  aboveWindows: !filePicker.running

  WlrLayershell.keyboardFocus: visible
    ? WlrKeyboardFocus.OnDemand
    : WlrKeyboardFocus.None

  function moveFocus(delta) {
    const maxIndex = WallpaperService.files.length
    focusIndex = Math.max(0, Math.min(maxIndex, focusIndex + delta))
    if (focusIndex > 0) list.positionViewAtIndex(focusIndex - 1, ListView.Contain)
  }

  function activateFocused() {
    if (focusIndex === 0) {
      openFilePicker()
    } else {
      const file = WallpaperService.files[focusIndex - 1]
      if (file) WallpaperService.selectFile(file.name)
    }
  }

  function openFilePicker() {
    if (!filePicker.running) filePicker.running = true
  }

  onVisibleChanged: {
    if (visible) {
      WallpaperService.refresh()
      focusIndex = WallpaperService.files.length > 0 ? 1 : 0
      keyHandler.forceActiveFocus()
    }
  }

  anchors {
    top: true
    left: true
    right: true
    bottom: true
  }

  MouseArea {
    anchors.fill: parent
    onClicked: EventBus.wallpaperVisible = false
  }

  Item {
    id: keyHandler
    anchors.fill: parent
    focus: true

    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape) {
        EventBus.wallpaperVisible = false
        event.accepted = true
      } else if (event.key === Qt.Key_Left) {
        wallpaper.moveFocus(-1)
        event.accepted = true
      } else if (event.key === Qt.Key_Right) {
        wallpaper.moveFocus(1)
        event.accepted = true
      } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
        wallpaper.activateFocused()
        event.accepted = true
      }
    }
  }

  Process {
    id: filePicker
    command: [
      "zenity",
      "--file-selection",
      "--title=Choose wallpaper",
      "--file-filter=Images | *.png *.jpg *.jpeg *.webp"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const path = text.trim()
        if (path.length > 0) WallpaperService.addFile(path)
      }
    }
  }

  ContainerRectangle {
    implicitHeight: Settings.wallpaperPanelHeight
    implicitWidth: wallpaper.panelWidth

    anchors.centerIn: parent

    MouseArea {
      anchors.fill: parent
    }

    RowLayout {
      anchors.fill: parent
      anchors.margins: Settings.marginMedium
      spacing: Settings.marginMedium

      ContainerRectangle {
        implicitWidth: Settings.wallpaperThumbnailSize
        implicitHeight: Settings.wallpaperThumbnailSize
        color: (wallpaper.focusIndex === 0 || addArea.containsMouse)
          ? Colors.primary_container
          : Colors.background
        border.width: Settings.border
        border.color: wallpaper.focusIndex === 0 ? Colors.secondary : Colors.outline

        ContainerLabel {
          anchors.centerIn: parent
          text: "+"
          font.pixelSize: Settings.fontSize * 1.5
          font.bold: true
        }

        MouseArea {
          id: addArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            wallpaper.focusIndex = 0
            wallpaper.openFilePicker()
          }
        }
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        orientation: ListView.Horizontal
        clip: true
        model: WallpaperService.files
        spacing: Settings.marginMedium

        ScrollBar.horizontal: StyledScrollBar {
          id: hbar
        }

        FastScroll {
          horizontal: true
          stepSize: Settings.wallpaperThumbnailSize + Settings.marginMedium
        }

        delegate: WallpaperThumbnail {
          focused: index === wallpaper.focusIndex - 1
          onClicked: wallpaper.focusIndex = index + 1
        }
      }
    }
  }
}
