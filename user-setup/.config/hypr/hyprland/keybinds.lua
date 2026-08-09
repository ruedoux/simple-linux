local terminal = os.getenv("TERMINAL")

hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + F", hl.dsp.exec_cmd("flatpak run app.zen_browser.zen"))
hl.bind("SUPER + E", hl.dsp.exec_cmd(terminal.." -e yazi"))
hl.bind("SUPER + R", hl.dsp.exec_cmd("qs ipc call menu toggle"))
hl.bind("SUPER + W", hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))
hl.bind("SUPER + C", hl.dsp.exec_cmd(terminal.." -e nvim"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd('grim -g "$(slurp -d)" - | wl-copy'))

hl.bind("SUPER + SHIFT + C", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/hyprlock-wrapper.sh"))
hl.bind("SUPER + X", hl.dsp.window.fullscreen())

-- Settings control
hl.bind("SUPER + EQUAL", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"))
hl.bind("SUPER + MINUS", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"))

-- Move window to another workspace
hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = "1", follow = false }))
hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = "2", follow = false }))
hl.bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = "3", follow = false }))
hl.bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = "4", follow = false }))
hl.bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = "5", follow = false }))
hl.bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = "6", follow = false }))

-- Move focus
hl.bind("SUPER + UP", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + DOWN", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + LEFT", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + RIGHT", hl.dsp.focus({ direction = "right" }))

-- Move window
hl.bind("SUPER + ALT + LEFT", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + ALT + RIGHT", hl.dsp.window.move({ direction = "right" }))
hl.bind("SUPER + ALT + UP", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + ALT + DOWN", hl.dsp.window.move({ direction = "down" }))

-- Move to workspace
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = "1" }))
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = "2" }))
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = "3" }))
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = "4" }))
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = "5" }))
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = "6" }))

-- Mouse
hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true })    -- ALT + LMB: Move a window
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })  -- ALT + RMB: Resize a window

hl.bind("SUPER + SHIFT + X", hl.dsp.window.float({ action = "toggle" }))
