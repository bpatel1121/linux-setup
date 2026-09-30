return {
  {
    "GCBallesteros/jupytext.nvim",
    opts = { style = "markdown", output_extension = "md", force_ft = "markdown" },
  },
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    build = ":UpdateRemotePlugins",
  },
  {
    "quarto-dev/quarto-nvim",
    dependencies = { "jmbuhr/otter.nvim", "nvim-treesitter/nvim-treesitter" },
    ft = { "quarto", "markdown" },
    opts = {
      lspFeatures = { languages = { "python" } },
      codeRunner = { enabled = true, default_method = "molten" },
    },
    config = function(_, opts)
      require("quarto").setup(opts)

      -- activate quarto in markdown buffers (including the one that triggered loading)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function()
          require("quarto").activate()
        end,
      })
      if vim.bo.filetype == "markdown" then
        require("quarto").activate()
      end

      local runner = require("quarto.runner")
      vim.keymap.set("n", "<localleader>mi", ":MoltenInit<CR>", { desc = "Molten init kernel" })
      vim.keymap.set("n", "<localleader>rc", runner.run_cell, { desc = "Run cell" })
      vim.keymap.set("n", "<localleader>ra", runner.run_above, { desc = "Run cells above" })
      vim.keymap.set("n", "<localleader>rA", runner.run_all, { desc = "Run all cells" })
      vim.keymap.set("v", "<localleader>r", ":<C-u>MoltenEvaluateVisual<CR>gv", { desc = "Run selection" })
    end,
  },
}
