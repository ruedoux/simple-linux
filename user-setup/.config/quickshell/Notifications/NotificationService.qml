pragma Singleton
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import ".."

Singleton {
  id: notificationService

  readonly property alias server: server
  readonly property var trackedNotifications: server.trackedNotifications
  property ListModel history: ListModel {}

  NotificationServer {
    id: server

    actionsSupported: true
    bodySupported: true
    imageSupported: true

    onNotification: n => {
      notificationService.history.insert(0, {
        summary: n.summary,
        body: n.body,
        appName: n.appName,
        urgency: n.urgency,
        time: Qt.formatDateTime(new Date(), Settings.dateFormatShort),
      })
      EventBus.unreadNotifications += 1
      n.tracked = true
    }
  }
}
