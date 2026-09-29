import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../Containers"

PanelWindow {
  property var modelData
  property alias isVisible: menu.visible

  property int selectedIndex: 0
  property var filtered: {
    const querry = searchInput.text.trim().toLowerCase()
    const apps = DesktopEntries.applications.values.filter(e => e && !e.noDisplay)
    const matched = querry === ""
      ? apps
      : apps.filter(e => e.name.toLowerCase().includes(querry))
    return matched.sort((a, b) => a.name.localeCompare(b.name))
  }

  function launch(entry) {
    if (!entry) return
    if (entry.runInTerminal) { Quickshell.execDetached([Settings.terminal, "-e", ...entry.command]) } 
    else { entry.execute()}
    EventBus.menuVisible = false
  }

  function reset() {
    searchInput.clear()
    selectedIndex = 0
  }

  function moveSelection(delta) {
    const count = filtered.length
    if (count === 0) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
    list.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  onFilteredChanged: {
    if (selectedIndex >= filtered.length)
      selectedIndex = Math.max(0, filtered.length - 1)
  }

  screen: modelData
  id: menu
  visible: false
  color: Colors.transparent

  WlrLayershell.keyboardFocus: visible
    ? WlrKeyboardFocus.OnDemand
    : WlrKeyboardFocus.None

  onVisibleChanged: {
    reset()
    if (visible) searchInput.forceActiveFocus()
  }

  anchors {
    top: true
    left: true
    right: true
    bottom: true
  }

  MouseArea {
    anchors.fill: parent
    onClicked: EventBus.menuVisible = false
    hoverEnabled: true
  }

  ContainerRectangle {
    implicitHeight: Settings.menuHeight
    implicitWidth: Settings.menuWidth

    anchors {
      top: parent.top
      left: parent.left
      topMargin: Settings.marginSmall
      leftMargin: Settings.marginSmall
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Settings.marginSmall
      spacing: Settings.marginSmall

      MenuSystemActions { }

      ContainerRectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Settings.fontSize * 2

        TextInput {
          id: searchInput
          anchors.fill: parent
          anchors.leftMargin: Settings.marginSmall
          anchors.rightMargin: Settings.marginSmall
          verticalAlignment: TextInput.AlignVCenter
          clip: true

          color: Colors.on_background
          selectionColor: Colors.primary_container
          selectedTextColor: Colors.on_primary_container
          font.family: Settings.fontFamily
          font.pixelSize: Settings.fontSize

          cursorDelegate: Rectangle {
            width: Settings.border
            color: Colors.primary

            SequentialAnimation on opacity {
              running: searchInput.cursorVisible
              loops: Animation.Infinite
              NumberAnimation { to: 0; duration: 0 }
              PauseAnimation { duration: 500 }
              NumberAnimation { to: 1; duration: 0 }
              PauseAnimation { duration: 500 }
            }
          }

          onTextChanged: menu.selectedIndex = 0

          Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) {
              menu.moveSelection(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              menu.moveSelection(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              menu.launch(menu.filtered[menu.selectedIndex])
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              EventBus.menuVisible = false
              event.accepted = true
            }
          }

          ContainerLabel {
            anchors.verticalCenter: parent.verticalCenter
            visible: searchInput.text === ""
            text: "Search…"
            color: Colors.outline
          }
        }
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: menu.filtered
        spacing: Settings.marginSmall
        currentIndex: menu.selectedIndex

        ScrollBar.vertical: StyledScrollBar {
          id: vbar
        }

        FastScroll {
          stepSize: Settings.menuItemSize + Settings.marginSmall
        }

        delegate: ContainerRectangle {
          id: row
          required property int index
          required property var modelData

          width: ListView.view.width - (vbar.visible ? vbar.width + Settings.marginSmall : 0)
          implicitHeight: rowLayout.implicitHeight + Settings.marginSmall * 2
          radius: Settings.radiusSize
          color: index === menu.selectedIndex
            ? Colors.surface_container_high
            : Colors.background
          border.color: index === menu.selectedIndex
            ? Colors.primary
            : Colors.outline

          RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.margins: Settings.marginSmall
            spacing: Settings.marginSmall

            IconImage {
              Layout.preferredWidth: Settings.fontSize
              Layout.preferredHeight: Settings.fontSize
              Layout.alignment: Qt.AlignVCenter
              visible: status === Image.Ready
              source: Quickshell.iconPath(row.modelData.icon, true)
            }

            ContainerLabel {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: row.modelData.name
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              menu.selectedIndex = row.index
              menu.launch(row.modelData)
            }
          }
        }
      }
    }
  }
}
