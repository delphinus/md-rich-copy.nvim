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
  H.eq(html:find("<li>✅ done 日本語</li>", 1, true) ~= nil, true, "task item")
  H.eq(clipboard "public.utf8-plain-text", table.concat(lines, "\n"), "plain text")
end)

H.test("local images are embedded in the HTML and carried by a web archive", function()
  -- A 1x1 PNG, and a vault where the embed is found by name alone.
  local png =
    vim.base64.decode "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg=="
  local vault = vim.fn.tempname()
  vim.fn.mkdir(vault .. "/.obsidian", "p")
  vim.fn.mkdir(vault .. "/notes", "p")
  vim.fn.mkdir(vault .. "/files", "p")
  for _, path in ipairs { "/files/a b.png", "/notes/c.png" } do
    local f = assert(io.open(vault .. path, "wb"))
    f:write(png)
    f:close()
  end
  require("md-rich-copy").copy({ "![[a b.png]] ![c](c.png) ![d](missing.png)" }, { base = vault .. "/notes" })
  vim.fn.delete(vault, "rf")
  local html = clipboard "public.html"
  local data = 'src="data:image/png;base64,' .. vim.base64.encode(png) .. '"'
  H.eq(select(2, html:gsub(vim.pesc(data), "")), 2, "data URLs")
  H.eq(html:find('src="missing.png"', 1, true) ~= nil, true, "missing image is left alone")
  local result = vim
    .system({ "osascript", "-l", "JavaScript", "-" }, {
      stdin = [[
ObjC.import("AppKit")
const data = $.NSPasteboard.generalPasteboard.dataForType("com.apple.webarchive")
const plist = $.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 0, null, null)
const subs = ObjC.deepUnwrap(plist.objectForKey("WebSubresources")) || []
subs.map((s) => s.WebResourceMIMEType + " " + s.WebResourceURL.replace(/.*\//, "")).join("\n")
]],
    })
    :wait()
  H.eq(result.stdout, "image/png a%20b.png\nimage/png c.png\n", "web archive subresources")
end)

H.test(":MdRichCopy copies a range of the buffer", function()
  vim.cmd.source "plugin/md-rich-copy.lua"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "skipped", "**bold**", "skipped" })
  vim.cmd "2MdRichCopy"
  H.eq(clipboard("public.html"):find("<p><strong>bold</strong></p>", 1, true) ~= nil, true, "range html")
  H.eq(clipboard "public.utf8-plain-text", "**bold**", "range plain text")
end)

H.finish()
