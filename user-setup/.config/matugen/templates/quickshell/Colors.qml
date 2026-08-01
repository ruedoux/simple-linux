pragma Singleton
import QtQuick
import Quickshell

QtObject {
  readonly property color transparent: "#00000000"
<* for name, value in colors *>
  readonly property color {{name}}: "{{value.default.hex}}"
<* endfor *>
}