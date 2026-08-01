require("hyprland/env")
require("hyprland/env-overrides")
require("hyprland/workspaces")
require("hyprland/keybinds")
require("hyprland/monitors")
require("hyprland/default-apps")
require("hyprland/colors")
require("hyprland/rules")
require("hyprland/user-overrides")

hl.config({
  general = {
    border_size = 4,
    gaps_in = 4,
    gaps_out = 8,
    allow_tearing = false,
    col = {
      active_border = { colors = { primary, primary }, angle = 45 },
      inactive_border = secondary,
    },
  },
  animations = { enabled = false },
  decoration = {
    rounding_power = 2.5,
    rounding = 18,
    blur = { enabled = false },
    shadow = { enabled = false }
  },
  misc = {
    force_default_wallpaper = 0,
    disable_hyprland_logo = true,
    background_color = surface,
  },
  input = {
    kb_layout  = os.getenv("SL_KB_LAYOUT") or "pl",
    follow_mouse = 1,
    mouse_refocus = true,
  }
})

hl.on("hyprland.start", function()
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")
  hl.exec_cmd("systemctl --user import-environment QT_QPA_PLATFORMTHEME")
  hl.exec_cmd("systemctl --user start hyprland-session.target")
  hl.exec_cmd("systemctl --user start hyprpolkitagent")

  hl.exec_cmd("hypridle")
  hl.exec_cmd("hyprctl setcursor " .. os.getenv("HYPRCURSOR_SIZE") .. " " .. os.getenv("HYPRCURSOR_THEME"))
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd("qs")
end)

hl.on("hyprland.shutdown", function()
  os.execute("systemctl --user stop hyprland-session.target && sleep 0.1")
end)
