//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import QtQuick
import "Bar"
import "Notifications"
import "Menu"
import "Wallpaper"

ShellRoot {
  id: root

  Timer {
    interval: 2000
    running: true
    repeat: false
    onTriggered: {
      EventBus.runDetached(["/usr/local/bin/sl-remind", "notify"], Settings.logPath)
      EventBus.runDetached(["/usr/local/bin/sl-remind", "check-update"], Settings.logPath)
    }
  }

  Bar {
    modelData: Settings.screen
  }

  NotificationCenter {
    modelData: Settings.screen
    isVisible: EventBus.notificationCenterVisible
  }

  NotificationPanel {
    modelData: Settings.screen
  }

  Menu {
    modelData: Settings.screen
    isVisible: EventBus.menuVisible
  }

  Wallpaper {
    modelData: Settings.screen
    isVisible: EventBus.wallpaperVisible
  }
}