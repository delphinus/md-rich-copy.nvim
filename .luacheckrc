-- Luacheck configuration for md-rich-copy.nvim
-- Docs: https://luacheck.readthedocs.io/en/stable/config.html

-- Neovim embeds LuaJIT.
std = "luajit"
cache = true

read_globals = { "vim" }

globals = { "vim.g" }

-- Line width is owned by StyLua (column_width in .stylua.toml).
ignore = { "631" }
