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

-- Per-scheme fixups, re-asserted after any colorscheme load:
--   gruvbox    — brighten CursorLineNr in the theme's active yellow (the
--                stock one is too quiet; the popping line number stays).
--   cyberdream — its neon-green strings dominate config-heavy files and
--                fight the desktop's pink/cyan/amber discipline. Retint
--                strings to cyan; green stays a STATE color, like the bar.
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("theme_fixups", { clear = true }),
    callback = function(ev)
        if ev.match == "gruvbox" then
            vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#fabd2f", bold = true })
        elseif ev.match == "cyberdream" then
            -- Retint to the Cybrcolors vocabulary the whole desktop speaks:
            -- pink = structure (keywords — the bulk of the pop), cyan =
            -- readouts (functions, strings), amber = literals. Green stays
            -- a state color, exactly like the bar.
            local pink, cyan, amber = "#F230B2", "#29BECC", "#F2D230"
            local fix = {
                Keyword = { fg = pink },            ["@keyword"] = { fg = pink },
                Statement = { fg = pink },          ["@keyword.function"] = { fg = pink },
                Conditional = { fg = pink },        Repeat = { fg = pink },
                Function = { fg = cyan, bold = true },
                ["@function"] = { fg = cyan, bold = true },
                String = { fg = cyan },             ["@string"] = { fg = cyan },
                Constant = { fg = amber },          Number = { fg = amber },
                Boolean = { fg = amber },
                CursorLineNr = { fg = pink, bold = true },
            }
            for group, hl in pairs(fix) do
                vim.api.nvim_set_hl(0, group, hl)
            end
        end
    end,
})

return {
    -- both schemes installed so SUPER+T never needs a plugin sync
    { "ellisonleao/gruvbox.nvim" },
    { "scottmckendry/cyberdream.nvim" },
    { "LazyVim/LazyVim", opts = { colorscheme = theme_colorscheme() } },
}
