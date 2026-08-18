-- Editor follows the desktop theme. Each theme dir in the hyprland repo ships
-- an nvim.lua token (`return "<colorscheme>"`); we read it through the
-- themes/current symlink at startup — same pattern wezterm uses for colors.
--
-- Applies to NEW nvim instances: an editor already open keeps its colors until
-- reopened (or `:colorscheme x` by hand). Hot-swapping live editors would need
-- server-socket plumbing — deliberately not worth the surface area.
local function theme_colorscheme()
    local token = (os.getenv("HOME") or "") .. "/.config/hypr/themes/current/nvim.lua"
    local ok, name = pcall(dofile, token)
    if ok and type(name) == "string" and #name > 0 then
        return name
    end
    return "tokyonight" -- LazyVim's default — sane when no theme is linked yet
end

return {
    -- both schemes installed so SUPER+T never needs a plugin sync
    { "ellisonleao/gruvbox.nvim" },
    { "scottmckendry/cyberdream.nvim" },
    { "LazyVim/LazyVim", opts = { colorscheme = theme_colorscheme() } },
}
