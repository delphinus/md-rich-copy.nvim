-- Test copying to the macOS clipboard end to end.
-- This overwrites the clipboard, so it runs only with MD_RICH_COPY_TEST_CLIPBOARD=1.
-- Run: MD_RICH_COPY_TEST_CLIPBOARD=1 nvim --headless -u NONE --noplugin -l tests/clipboard_test.lua

local H = require "tests.helper"

if vim.fn.has "mac" == 0 or os.getenv "MD_RICH_COPY_TEST_CLIPBOARD" ~= "1" then
  print "SKIP: set MD_RICH_COPY_TEST_CLIPBOARD=1 on macOS to run the clipboard test"
  H.finish()
  return
end

local GET_CLIPBOARD = [[
use framework "AppKit"
on run argv
  set pb to current application's NSPasteboard's generalPasteboard()
  return (pb's stringForType:(item 1 of argv)) as text
end run
]]

--- Read one flavor of the clipboard as text.
local function clipboard(type)
  local result = vim.system({ "osascript", "-", type }, { stdin = GET_CLIPBOARD }):wait()
  assert(result.code == 0, result.stderr)
  return (result.stdout:gsub("\n$", ""))
end

H.test("copy puts HTML and the Markdown source on the clipboard", function()
  local lines = { "# Title", "", "- [x] done 日本語" }
  require("md-rich-copy").copy(lines)
  local html = clipboard "public.html"
  H.eq(html:find('<meta http-equiv="Content-Type" content="text/html; charset=utf-8">', 1, true) == 1, true, "meta")
  H.eq(html:find("<h1>Title</h1>", 1, true) ~= nil, true, "heading")
  H.eq(html:find("<li>☑ done 日本語</li>", 1, true) ~= nil, true, "task item")
  H.eq(clipboard "public.utf8-plain-text", table.concat(lines, "\n"), "plain text")
end)

H.test(":MdRichCopy copies a range of the buffer", function()
  vim.cmd.source "plugin/md-rich-copy.lua"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "skipped", "**bold**", "skipped" })
  vim.cmd "2MdRichCopy"
  H.eq(clipboard("public.html"):find("<p><strong>bold</strong></p>", 1, true) ~= nil, true, "range html")
  H.eq(clipboard "public.utf8-plain-text", "**bold**", "range plain text")
end)

H.finish()
