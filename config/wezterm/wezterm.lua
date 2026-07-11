-- WezTerm config · theme-aware (reads the active Hyprland theme's colors)
local wezterm = require("wezterm")
local config  = wezterm.config_builder and wezterm.config_builder() or {}

config.font = wezterm.font_with_fallback({ "JetBrains Mono", "Noto Color Emoji" })
config.font_size         = 12.0
config.enable_tab_bar    = false
config.window_padding    = { left = 10, right = 10, top = 8, bottom = 8 }
config.window_background_opacity = 0.92

-- Pull colors from the currently active theme (falls back to WezTerm's default
-- if the theme has no wezterm/colors.lua yet).
local home = os.getenv("HOME")
local ok, colors = pcall(dofile, home .. "/.config/hypr/themes/current/wezterm/colors.lua")
if ok and type(colors) == "table" then
    config.colors = colors
end

return config
