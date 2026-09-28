-- Convert Markdown to HTML with pandoc and put it on the macOS clipboard as rich text.
--
-- The HTML is tuned so that it pastes cleanly into Mail.app, Confluence, Jira and
-- Slack. Each tweak in M.adjust() exists because one of them mishandled pandoc's
-- plain output; see the comments there.
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

--- Rewrite pandoc's HTML so that it survives pasting into the targets above.
---@param html string HTML produced by `pandoc -f gfm -t html`
---@return string
function M.adjust(html)
  -- Task lists: <input> checkboxes vanish in Confluence, Jira and Slack.
  html = html
    :gsub('<label><input type="checkbox" checked="" />', "☑ ")
    :gsub('<label><input type="checkbox" />', "☐ ")
    :gsub("</label>", "")
    :gsub('<ul class="task%-list">', "<ul>")
  -- Strikethrough: Jira reads only <del>, Slack reads only <s>.
  html = html:gsub("<del>", "<del><s>"):gsub("</del>", "</s></del>")
  -- Mail.app draws no table borders or quote bar without styles. Add only those,
  -- and leave font sizes and colors to the target so its defaults win.
  local cell = "border:1px solid #999; padding:4px 8px;"
  html = html
    :gsub("<table>", '<table style="border-collapse:collapse;">')
    :gsub('<(t[hd]) style="([^"]*)">', function(tag, style)
      return ('<%s style="%s %s">'):format(tag, cell, style)
    end)
    :gsub("<(t[hd])>", function(tag)
      return ('<%s style="%s">'):format(tag, cell)
    end)
    :gsub("<blockquote>", '<blockquote style="border-left:3px solid #ccc; margin-left:0; padding-left:12px;">')
  -- Code blocks: Jira collapses newlines inside <pre>, so use <br> instead.
  html = html:gsub("<pre[^>]*><code[^>]*>\n?(.-)</code></pre>", function(body)
    return "<pre><code>" .. body:gsub("\n", "<br>") .. "</code></pre>"
  end)
  return html
end

--- Convert Markdown to the adjusted HTML.
---@param markdown string
---@return string
function M.to_html(markdown)
  -- pandoc >= 3.8 warns that --no-highlight is deprecated, but the replacement
  -- (--syntax-highlighting=none) does not exist in older versions.
  local result = vim.system({ "pandoc", "-f", "gfm", "-t", "html", "--no-highlight" }, { stdin = markdown }):wait()
  if result.code ~= 0 then error("pandoc failed: " .. result.stderr, 0) end
  return M.adjust(result.stdout)
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
  elseif vim.fn.executable "pandoc" == 0 then
    vim.notify("md-rich-copy: pandoc not found", vim.log.levels.ERROR)
    return
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
