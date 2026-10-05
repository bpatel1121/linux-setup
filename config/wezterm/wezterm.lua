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
--
-- Read from the RENDERED copy, not from themes/current/wezterm/colors.lua: a
-- watch on the symlinked path resolves to whichever theme file it pointed at
-- when the watch was set, and repointing the symlink changes nothing about
-- that file, so open terminals kept the old colors. theme-apply.sh copies the
-- active theme's colors to this path on every switch, which is a real content
-- change, which is what the watcher reacts to.
local home = os.getenv("HOME")
local theme_colors = home .. "/.config/hypr/wezterm-colors.lua"
local ok, colors = pcall(dofile, theme_colors)
if ok and type(colors) == "table" then
    config.colors = colors
end

-- WezTerm only auto-reloads when a *watched* file changes, and dofile'd files
-- aren't watched by default. Watching the rendered colors file makes open
-- terminals recolor live on SUPER+T theme switches instead of only new ones.
wezterm.add_to_config_reload_watch_list(theme_colors)

return config
