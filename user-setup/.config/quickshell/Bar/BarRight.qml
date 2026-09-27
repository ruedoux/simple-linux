import QtQuick
import QtQuick.Layouts
import "../Containers"
import "../Notifications"
import "../Tray"
import ".."

Item {
  Layout.fillWidth: true
  implicitHeight: parent.height

  readonly property bool hasUnreadNotifications: EventBus.unreadNotifications > 0

  RowLayout {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Settings.marginSmall

    ContainerRectangle {
      implicitWidth: themeModeRow.implicitWidth + Settings.marginBig

      ContainerLabel {
        id: themeModeRow
        anchors.centerIn: parent
        text: "󰃜"
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          EventBus.runDetached([Settings.slControllerPath, "switch-theme-mode"], Settings.logFile)
        }
      }
    }

    ContainerRectangle {
      implicitWidth: wallpaperRow.implicitWidth + Settings.marginBig
      color: EventBus.wallpaperVisible ? Colors.primary : Colors.background

      ContainerLabel {
        id: wallpaperRow
        anchors.centerIn: parent
        color: EventBus.wallpaperVisible ? Colors.on_primary : Colors.on_background
        text: "󰸉"
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          EventBus.wallpaperVisible = !EventBus.wallpaperVisible
        }
      }
    }

    ContainerRectangle {
      implicitWidth: statusRow.implicitWidth + Settings.marginBig
      color: BarServices.processApp.running ? Colors.primary : Colors.background

      RowLayout {
        id: statusRow
        anchors.centerIn: parent
        spacing: Settings.marginMedium

        ContainerLabel {
          text: "󰍛" + String(BarServices.cpuUsage).padStart(3) + "%"
          color: BarServices.processApp.running ? Colors.on_primary : Colors.on_background
        }

        ContainerLabel {
          text: "" + String(BarServices.memUsage).padStart(3) + "%"
          color: BarServices.processApp.running ? Colors.on_primary : Colors.on_background
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          BarServices.processApp.running = !BarServices.processApp.running
        }
      }
    }

    ContainerRectangle {
      implicitWidth: volumeRow.implicitWidth + Settings.marginBig
      color: BarServices.volumeApp.running ? Colors.primary : Colors.background

      ContainerLabel {
        id: volumeRow
        anchors.centerIn: parent
        color: BarServices.volumeApp.running ? Colors.on_primary : Colors.on_background
        text: " " + String(BarServices.volume).padStart(3) + "%"
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          BarServices.volumeApp.running = !BarServices.volumeApp.running
        }
      }
    }

    ContainerRectangle {
      implicitWidth: networkRow.implicitWidth + Settings.marginBig
      color: BarServices.networkApp.running ? Colors.primary : Colors.background

      ContainerLabel {
        id: networkRow
        anchors.centerIn: parent
        text: "󰣺 " + BarServices.network
        color: BarServices.networkApp.running ? Colors.on_primary : Colors.on_background
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          BarServices.networkApp.running = !BarServices.networkApp.running
        }
      }
    }

    Tray {}

    ContainerRectangle {
      implicitWidth: notificationRow.implicitWidth + Settings.marginBig
      color: (EventBus.notificationCenterVisible || hasUnreadNotifications) ? Colors.primary : Colors.background

      ContainerLabel {
        id: notificationRow
        anchors.centerIn: parent
        color: (EventBus.notificationCenterVisible || hasUnreadNotifications) ? Colors.on_primary : Colors.on_background
        text: ""
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          EventBus.notificationCenterVisible = !EventBus.notificationCenterVisible
        }
      }
    }

    ContainerRectangle {
      implicitWidth: timeRow.implicitWidth + Settings.marginBig

      ContainerLabel {
        id: timeRow
        anchors.centerIn: parent
        text: "󰥔 " + BarServices.time
      }
    }
  }
}
