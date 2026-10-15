-- Minimal Neovim config for quick edits. No plugins, starts instantly.
-- (On Omarchy, its LazyVim setup is used instead and this isn't installed.)

vim.g.mapleader = " "

local o = vim.opt
o.number = true
o.mouse = "a"
o.clipboard = "unnamedplus"   -- yank/paste use the system clipboard
o.ignorecase = true           -- search is case-insensitive...
o.smartcase = true            -- ...unless it has a capital
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true
o.undofile = true             -- undo history survives closing the file
o.scrolloff = 5
o.splitright = true
o.splitbelow = true
o.signcolumn = "yes"
o.termguicolors = true
o.wrap = false

local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<cr>")       -- clear search highlight
map("n", "<leader>w", "<cmd>write<cr>")        -- space w: save
map("n", "<leader>q", "<cmd>quit<cr>")         -- space q: quit
map("n", "<leader>e", "<cmd>Explore<cr>")      -- space e: file browser
map("v", "<", "<gv")                           -- keep selection when indenting
map("v", ">", ">gv")

-- Briefly highlight what was yanked
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() (vim.hl or vim.highlight).on_yank() end,
})
