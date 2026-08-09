pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  // Overrides
  readonly property string monitorName: "${SL_MAIN_MONITOR}"
  readonly property real scale: ${SL_UI_SCALE} * 0.7
  readonly property string fontFamily: "${SL_FONT}"
  readonly property int fontSize: ${SL_FONT_SIZE} * scale
  readonly property string terminal: "${SL_TERMINAL}"
  
  // Screen
  // Poll until the configured main monitor appears, then lock in.
  // No fallback — avoids rendering the bar on the wrong monitor when
  // screens are detected out of order during cold boot.
  // After hyprlock login, qs is fully restarted with a fresh screen reference.
  property var screen

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      const correct = Quickshell.screens.find(s => s.name === monitorName)
      if (correct) {
        screen = correct
        stop()
      }
    }
  }
  readonly property real screenWidth: screen?.width ?? 1920
  readonly property real screenHeight: screen?.height ?? 1080

  // Margins
  readonly property int border: Math.max(1, Math.round(2))
  readonly property int marginBig: Math.round(12 * scale)
  readonly property int marginMedium: Math.round(6 * scale)
  readonly property int marginSmall: Math.round(3 * scale)
  readonly property int radiusSize: Math.round(4 * scale)

  // Bar
  readonly property int barHeight: Math.round(fontSize * 1.6)
  readonly property int workspaceNumber: 6
  readonly property string dateFormat: "HH:mm yyyy/MM/dd"
  readonly property string dateFormatShort: "HH:mm"

  // Notifications
  readonly property int notificationTimeoutMs: 5000
  readonly property int notificationWidth: fontSize * 20

  // Menu
  readonly property int menuHeight: Math.round(screenHeight * 0.55)
  readonly property int menuWidth: Math.round(screenWidth * 0.31)
  readonly property int menuItemSize: Math.round(fontSize * 2)

  // Wallpaper
  readonly property int wallpaperPanelHeight: Math.round(fontSize * 8)
  readonly property int wallpaperThumbnailSize: wallpaperPanelHeight - marginMedium * 2
  readonly property int wallpaperThumbnailCount: Math.max(1, Math.floor((screenWidth * 0.6) / (wallpaperThumbnailSize + marginMedium)))
  readonly property int wallpaperPanelWidth: (wallpaperThumbnailCount + 1) * wallpaperThumbnailSize
    + wallpaperThumbnailCount * marginMedium + marginMedium * 2
  readonly property string wallpapersDir: Quickshell.env("HOME") + "/.config/simple-linux/files/wallpapers"
  readonly property string slControllerPath: Quickshell.env("HOME") + "/.config/simple-linux/sl-controller.sh"
  readonly property string logPath: Quickshell.env("HOME") + "/.config/simple-linux/qs.log"
}
