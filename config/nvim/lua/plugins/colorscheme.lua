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

-- gruvbox styles CursorLineNr quieter than tokyonight does, and the current
-- line number popping is worth keeping — re-assert it in gruvbox's own accent
-- (the same "active" yellow the bar uses). tokyonight already pops by default.
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("theme_cursorlinenr", { clear = true }),
    callback = function(ev)
        if ev.match == "gruvbox" then
            vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#fabd2f", bold = true })
        end
    end,
})

return {
    -- gruvbox installed alongside LazyVim's stock tokyonight, so SUPER+T
    -- never needs a plugin sync
    { "ellisonleao/gruvbox.nvim" },
    { "LazyVim/LazyVim", opts = { colorscheme = theme_colorscheme() } },
}
