pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: eventBus

  property bool notificationCenterVisible: false
  property bool menuVisible: false
  property bool wallpaperVisible: false

  IpcHandler {
    target: "notifications"
    function toggle(): void { notificationCenterVisible = !notificationCenterVisible }
    function show(): void { notificationCenterVisible = true }
    function hide(): void { notificationCenterVisible = false }
  }

  IpcHandler {
    target: "menu"
    function toggle(): void { menuVisible = !menuVisible }
    function show(): void { menuVisible = true }
    function hide(): void { menuVisible = false }
  }

  IpcHandler {
    target: "wallpaper"
    function toggle(): void { wallpaperVisible = !wallpaperVisible }
    function show(): void { wallpaperVisible = true }
    function hide(): void { wallpaperVisible = false }
  }

  function runDetached(command, logFile) {
    const quotedCommand = command.map(shellQuote).join(" ");
    const cmdStr = `exec setsid ${quotedCommand} >${shellQuote(logFile)} 2>&1 </dev/null`;
    Quickshell.execDetached(["sh", "-c", cmdStr]);
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }
}