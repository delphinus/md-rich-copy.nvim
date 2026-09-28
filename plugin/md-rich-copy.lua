if vim.g.loaded_md_rich_copy then return end
vim.g.loaded_md_rich_copy = true

vim.api.nvim_create_user_command("MdRichCopy", function(opts)
  require("md-rich-copy").copy_range(opts.line1, opts.line2)
end, { range = "%", bar = true, desc = "Copy Markdown to the clipboard as rich text" })
