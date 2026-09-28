-- Test the HTML rewriting in lua/md-rich-copy/init.lua
-- Run: nvim --headless -u NONE --noplugin -l tests/adjust_test.lua

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local M = require "md-rich-copy"

local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
  if actual == expected then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    print("FAIL: " .. msg)
    print("  expected: " .. vim.inspect(expected))
    print("  actual:   " .. vim.inspect(actual))
  end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    fail_count = fail_count + 1
    print("ERROR: " .. name .. ": " .. tostring(err))
  end
end

test("task list checkboxes become characters", function()
  local html = table.concat({
    '<ul class="task-list">',
    '<li><label><input type="checkbox" />todo</label></li>',
    '<li><label><input type="checkbox" checked="" />done</label></li>',
    "</ul>",
  }, "\n")
  assert_eq(M.adjust(html), "<ul>\n<li>☐ todo</li>\n<li>☑ done</li>\n</ul>", "task list")
end)

test("strikethrough is wrapped in both del and s", function()
  assert_eq(M.adjust "<p><del>x</del></p>", "<p><del><s>x</s></del></p>", "strikethrough")
end)

test("table cells get borders and keep alignment", function()
  local cell = "border:1px solid #999; padding:4px 8px;"
  assert_eq(M.adjust "<table>", '<table style="border-collapse:collapse;">', "table")
  assert_eq(M.adjust "<th>a</th>", ('<th style="%s">a</th>'):format(cell), "plain th")
  assert_eq(
    M.adjust '<td style="text-align: right;">b</td>',
    ('<td style="%s text-align: right;">b</td>'):format(cell),
    "aligned td"
  )
end)

test("blockquote gets a left bar", function()
  assert_eq(
    M.adjust "<blockquote>",
    '<blockquote style="border-left:3px solid #ccc; margin-left:0; padding-left:12px;">',
    "blockquote"
  )
end)

test("code block newlines become br", function()
  assert_eq(
    M.adjust '<pre class="lua"><code>a = 1\nb = 2</code></pre>\n<pre><code>\nc\n</code></pre>',
    "<pre><code>a = 1<br>b = 2</code></pre>\n<pre><code>c<br></code></pre>",
    "code blocks"
  )
end)

test("inline code and paragraphs are untouched", function()
  local html = "<p>a <code>b</code> <strong>c</strong></p>"
  assert_eq(M.adjust(html), html, "untouched")
end)

if vim.fn.executable "pandoc" == 1 then
  test("to_html runs pandoc end to end", function()
    local html = M.to_html "- [x] done\n\n~~gone~~\n\n```lua\nlocal a\nlocal b\n```\n"
    assert_eq(html:find("☑ done", 1, true) ~= nil, true, "task item")
    assert_eq(html:find("<del><s>gone</s></del>", 1, true) ~= nil, true, "strikethrough")
    assert_eq(html:find("<pre><code>local a<br>local b</code></pre>", 1, true) ~= nil, true, "code block")
  end)
else
  print "SKIP: pandoc not found; to_html test skipped"
end

print(("%d passed, %d failed"):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
