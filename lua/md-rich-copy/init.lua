-- Convert Markdown to HTML and put it on the macOS clipboard as rich text.
--
-- The conversion lives in md-rich-copy/html.lua; this module handles the clipboard.
local M = {}

local META = [[<meta http-equiv="Content-Type" content="text/html; charset=utf-8">]]

-- Put both HTML and plain text on the pasteboard. Slack refuses to paste at all
-- when there is no plain-text flavor, even though it reads the HTML one.
local SET_CLIPBOARD = [[
use framework "AppKit"
on run argv
  set pb to current application's NSPasteboard's generalPasteboard()
  pb's clearContents()
  set h to (current application's NSData's dataWithContentsOfFile:(item 1 of argv))
  pb's setData:h forType:(current application's NSPasteboardTypeHTML)
  set t to (current application's NSString's stringWithContentsOfFile:(item 2 of argv) encoding:4 |error|:(missing value))
  pb's setString:t forType:(current application's NSPasteboardTypeString)
end run
]]

--- Convert Markdown to HTML adjusted for pasting.
---@param markdown string
---@return string
function M.to_html(markdown)
  return require("md-rich-copy.html").convert(markdown)
end

--- Copy Markdown lines to the clipboard as rich text, with the source as plain text.
---@param lines string[]
function M.copy(lines)
  local html = META .. "\n" .. M.to_html(table.concat(lines, "\n"))
  local html_file, text_file = vim.fn.tempname(), vim.fn.tempname()
  vim.fn.writefile(vim.split(html, "\n"), html_file, "b")
  vim.fn.writefile(lines, text_file, "b")
  local ok, result = pcall(function()
    return vim.system({ "osascript", "-", html_file, text_file }, { stdin = SET_CLIPBOARD }):wait()
  end)
  vim.fn.delete(html_file)
  vim.fn.delete(text_file)
  if not ok then
    error(result, 0)
  elseif result.code ~= 0 then
    error("osascript failed: " .. result.stderr, 0)
  end
end

--- Copy a line range of the current buffer. This is what :MdRichCopy calls.
---@param line1 integer
---@param line2 integer
function M.copy_range(line1, line2)
  if vim.fn.has "mac" == 0 then
    vim.notify("md-rich-copy: only macOS is supported", vim.log.levels.ERROR)
    return
  end
  for _, lang in ipairs { "markdown", "markdown_inline" } do
    -- language.add() throws on failure in 0.10 and returns nil, err from 0.11.
    local ok, res, err = pcall(vim.treesitter.language.add, lang)
    if not ok or err then
      local msg = ("md-rich-copy: tree-sitter parser %q is not available: %s"):format(lang, ok and err or res)
      vim.notify(msg, vim.log.levels.ERROR)
      return
    end
  end
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  local ok, err = pcall(M.copy, lines)
  if ok then
    vim.notify(("md-rich-copy: copied %d lines as rich text"):format(#lines))
  else
    vim.notify("md-rich-copy: " .. err, vim.log.levels.ERROR)
  end
end

return M
