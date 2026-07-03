

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.enable_wayland = true
config.front_end = "Software"

return config
