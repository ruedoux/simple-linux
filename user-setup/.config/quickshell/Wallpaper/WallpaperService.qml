pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import ".."

Singleton {
  id: wallpaperService

  property var files: []
  property string selected: ""

  function parseIndex(name) {
    const match = name.match(/-(\d+)\.[^.]+$/)
    return match ? parseInt(match[1]) : -1
  }

  function refresh() {
    listProcess.running = true
    selectedProcess.running = true
  }

  function _runUpdateWallpaper(path) {
    EventBus.runDetached([Settings.slControllerPath, "update-wallpaper", "--path", path], Settings.logFile)
    EventBus.wallpaperVisible = false
  }

  function selectFile(name) {
    _runUpdateWallpaper(Settings.wallpapersDir + "/" + name)
  }

  function deleteFile(name) {
    Qt.callLater(() => {
      deleteProcess.command = ["sh", "-c", "'" + Settings.slControllerPath + "' remove-wallpaper --name '" + name + "'"]
      deleteProcess.running = true
    })

    if (selected === name) selected = ""
    files = files.filter(f => f.name !== name)
  }

  function addFile(path) {
    addProcess.command = [Settings.slControllerPath, "update-wallpaper", "--path", path]
    addProcess.running = true
  }

  Process {
    id: listProcess
    command: ["sh", "-c", "ls -1 '" + Settings.wallpapersDir + "' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n").filter(l => l.length > 0 && l !== ".selected")
        const parsed = lines.map(name => ({
          name: name,
          path: Settings.wallpapersDir + "/" + name,
          index: wallpaperService.parseIndex(name)
        }))
        parsed.sort((a, b) => a.index - b.index)
        wallpaperService.files = parsed
      }
    }
  }

  Process {
    id: selectedProcess
    command: ["sh", "-c", "cat '" + Settings.wallpapersDir + "/.selected' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: wallpaperService.selected = text.trim()
    }
  }

  Process {
    id: deleteProcess
    onExited: wallpaperService.refresh()
  }

  Process {
    id: addProcess
    onExited: wallpaperService.refresh()
  }

  Component.onCompleted: {
    selectedProcess.running = true
    listProcess.running = true
  }
}
