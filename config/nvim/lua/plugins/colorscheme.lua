-- Editor follows the desktop theme — MECHANISM ONLY. Each theme dir in the
-- hyprland repo ships an nvim.lua token returning
--   { colorscheme = "<name>", highlights = { <group> = <hl>, ... } }
-- read through the themes/current symlink at startup; the colors live with
-- the theme, like every other surface. Same pattern wezterm uses.
--
-- Applies to NEW nvim instances: an editor already open keeps its colors
-- until reopened. Hot-swapping live editors would need server-socket
-- plumbing — deliberately not worth the surface area.
local function theme()
    local token = (os.getenv("HOME") or "") .. "/.config/hypr/themes/current/nvim.lua"
    local ok, t = pcall(dofile, token)
    if ok and type(t) == "table" and type(t.colorscheme) == "string" then
        return t
    end
    return { colorscheme = "tokyonight" } -- sane when no theme is linked yet
end
local T = theme()

-- Re-apply the theme's highlight fixups after its scheme loads (a bare
-- :colorscheme would otherwise wipe them).
if T.highlights then
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("theme_highlights", { clear = true }),
        pattern = T.colorscheme,
        callback = function()
            for group, hl in pairs(T.highlights) do
                vim.api.nvim_set_hl(0, group, hl)
            end
        end,
    })
end

return {
    -- Every scheme a theme token may name must be installed here — the one
    -- provisioning-side coupling. A new theme naming a new scheme adds its
    -- plugin to this list.
    { "ellisonleao/gruvbox.nvim" },
    { "scottmckendry/cyberdream.nvim" },
    { "LazyVim/LazyVim", opts = { colorscheme = T.colorscheme } },
}
