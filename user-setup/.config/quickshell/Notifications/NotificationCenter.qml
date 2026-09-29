import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../Containers"

PanelWindow {
  property var modelData
  property alias isVisible: notificationCenter.visible

  id: notificationCenter
  screen: modelData
  color: Colors.transparent

  WlrLayershell.keyboardFocus: visible
    ? WlrKeyboardFocus.OnDemand
    : WlrKeyboardFocus.None

  onVisibleChanged: {
    if (visible) {
      keyHandler.forceActiveFocus()
      EventBus.unreadNotifications = 0
    }
  }

  anchors {
    top: true
    right: true
    left: true
    bottom: true
  }

  MouseArea {
    anchors.fill: parent
    onClicked: EventBus.notificationCenterVisible = false
  }

  ContainerRectangle {
    implicitWidth: Settings.notificationWidth
    implicitHeight: Math.min(column.implicitHeight + Settings.marginMedium * 2, modelData.height * 0.6)

    anchors {
      top: parent.top
      right: parent.right
      topMargin: Settings.marginSmall
      rightMargin: Settings.marginMedium + Settings.marginSmall
    }

    MouseArea {
      anchors.fill: parent
    }

    Item {
      id: keyHandler
      anchors.fill: parent
      focus: true

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
          EventBus.notificationCenterVisible = false
          event.accepted = true
        }
      }
    }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: Settings.marginMedium 
      width: parent.width
      spacing: Settings.marginMedium

      RowLayout {
        Layout.fillWidth: true

        ContainerLabel {
          Layout.fillWidth: true
          text: "Notifications"
          font.bold: true
        }

        ContainerRectangle {
          visible: NotificationService.history.count > 0
          implicitWidth: clearLabel.implicitWidth + Settings.marginSmall * 2
          implicitHeight: clearLabel.implicitHeight + Settings.marginSmall * 2

          ContainerLabel {
            id: clearLabel
            anchors.centerIn: parent
            text: "Clear all"
            color: Colors.error
          }

          MouseArea {
            anchors.fill: parent
            onClicked: NotificationService.history.clear()
          }
        }
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: contentHeight
        clip: true
        model: NotificationService.history
        spacing: Settings.marginMedium

        ScrollBar.vertical: StyledScrollBar {
          id: vbar
        }

        FastScroll {
          stepSize: Settings.menuItemSize + Settings.marginMedium
        }

        delegate: ContainerRectangle {
            id: card
            required property int index
            required property var model

            width: ListView.view.width - (vbar.visible ? vbar.width + Settings.marginSmall : 0)
            implicitHeight: layout.implicitHeight + Settings.marginMedium * 2
            radius: Settings.radiusSize
            border.color: card.model.urgency === NotificationUrgency.Critical
              ? Colors.error : Colors.outline

            ColumnLayout {
              id: layout
              anchors.fill: parent
              anchors.margins: Settings.marginMedium
              spacing: Settings.marginSmall

              RowLayout {
                Layout.fillWidth: true
                spacing: Settings.marginMedium

                ContainerLabel {
                  Layout.fillWidth: true
                  text: card.model.summary
                  elide: Text.ElideRight
                  font.bold: true
                }

                ContainerLabel {
                  text: card.model.time
                  color: Colors.outline
                }

                ContainerLabel {
                  id: removeContainer
                  text: ""
                  font.bold: true
                  color: Colors.error

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.history.remove(card.index)
                  }
                }
              }

              ContainerLabel {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.model.body
                wrapMode: Text.WordWrap
              }

              ContainerLabel {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.model.appName
                color: Colors.outline
                font.pixelSize: Settings.fontSize - 2
              }
            }
          }
        }
      }
    }
  }
