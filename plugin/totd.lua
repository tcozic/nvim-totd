-- plugin/totd.lua
-- Neovim plugin shim. Required so the plugin is discovered by the runtime.
-- The actual bootstrap happens when the user calls require('totd').setup().
-- Nothing is executed here that could cause startup overhead.
if vim.g.loaded_totd then return end
vim.g.loaded_totd = 1
