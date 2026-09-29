local terminal = os.getenv("TERMINAL")
local workspace_count = tonumber(os.getenv("SL_WORKSPACE_COUNT"))

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
for i = 1, workspace_count do
  hl.bind("SUPER + SHIFT + " .. i, hl.dsp.window.move({ workspace = tostring(i), follow = false }))
end

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
for i = 1, workspace_count do
  hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
end

-- Mouse
hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true })    -- ALT + LMB: Move a window
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })  -- ALT + RMB: Resize a window

hl.bind("SUPER + SHIFT + X", hl.dsp.window.float({ action = "toggle" }))
