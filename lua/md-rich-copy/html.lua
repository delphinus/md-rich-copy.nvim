-- Convert Markdown to HTML with the tree-sitter parsers bundled with Neovim
-- (markdown and markdown_inline), so that no external converter is needed.
--
-- The HTML is tuned so that it pastes cleanly into Mail.app, Confluence, Jira and
-- Slack. Each tweak is commented where it is emitted.
local M = {}

-- Mail.app draws no table borders or quote bar without styles. Add only those, and
-- leave font sizes and colors to the target so its defaults win.
local TABLE_STYLE = "border-collapse:collapse;"
local CELL_STYLE = "border:1px solid #999; padding:4px 8px;"
local QUOTE_STYLE = "border-left:3px solid #ccc; margin-left:0; padding-left:12px;"

-- Characters that may appear in a bare URL. Stopping at anything else (including
-- non-ASCII) keeps "https://example.comを参照" from swallowing the Japanese text.
local URL_CHAR = "[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]"

local function escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function escape_attr(s)
  return (escape(s):gsub('"', "&quot;"))
end

local function range(node)
  local _, _, s = node:start()
  local _, _, e = node:end_()
  return s, e
end

local function parse(text, lang)
  return vim.treesitter.get_string_parser(text, lang):parse()[1]:root()
end

local function child_of_type(node, type)
  for child in node:iter_children() do
    if child:type() == type then return child end
  end
end

--- Find the next bare URL (GFM extended autolink) in s at or after init.
---@return integer? start
---@return integer? finish
local function next_url(s, init)
  local best
  for _, prefix in ipairs { "https?://%w", "www%.%w" } do
    local a = s:find(prefix, init)
    while a and a > 1 and s:sub(a - 1, a - 1):match "%w" do
      a = s:find(prefix, a + 1)
    end
    if a and (not best or a < best) then best = a end
  end
  if not best then return end
  local _, b = s:find("^" .. URL_CHAR .. "+", best)
  -- Trailing punctuation belongs to the sentence, and so does an unbalanced ")".
  while b > best do
    local c = s:sub(b, b)
    if c:match "[%?!%.,:%*_~']" then
      b = b - 1
    elseif c == ")" and select(2, s:sub(best, b):gsub("%)", "")) > select(2, s:sub(best, b):gsub("%(", "")) then
      b = b - 1
    else
      break
    end
  end
  return best, b
end

--- Escape plain text, turning bare URLs into links as GFM does.
local function text_html(s)
  local out, pos = {}, 1
  while true do
    local a, b = next_url(s, pos)
    if not a then break end
    local url = s:sub(a, b)
    local href = url:match "^www%." and "http://" .. url or url
    table.insert(out, escape(s:sub(pos, a - 1)))
    table.insert(out, ('<a href="%s">%s</a>'):format(escape_attr(href), escape(url)))
    pos = b + 1
  end
  table.insert(out, escape(s:sub(pos)))
  return table.concat(out)
end

local function code_block(body)
  -- Jira joins the lines of a <pre> into one, so break them with <br>.
  return "<pre><code>" .. escape(body):gsub("\n", "<br>") .. "</code></pre>"
end

local function unescape_punct(s)
  return (s:gsub("\\(%p)", "%1"))
end

local function link_label(s)
  return vim.trim(s:gsub("^%[", ""):gsub("%]$", "")):gsub("%s+", " "):lower()
end

---@class md_rich_copy.Converter
---@field src string
---@field lines string[]
---@field refs table<string, {href: string, title: string?}>
---@field continuation_end table<integer, integer> row -> column where its continuation ends
local Converter = {}
Converter.__index = Converter

function Converter:text(node)
  local s, e = range(node)
  return self.src:sub(s + 1, e)
end

--- Text of node with the block markers of continuation lines (">", indentation)
--- cut out.
function Converter:strip_continuations(node)
  local s, e = range(node)
  local parts, pos = {}, s
  for child in node:iter_children() do
    if child:type() == "block_continuation" then
      local cs, ce = range(child)
      table.insert(parts, self.src:sub(pos + 1, cs))
      pos = ce
    end
  end
  table.insert(parts, self.src:sub(pos + 1, e))
  return table.concat(parts)
end

function Converter:is_blank_row(row)
  -- ">" alone is a blank line inside a block quote.
  return (self.lines[row + 1] or ""):match "^[%s>]*$" ~= nil
end

--- The last row of node that has content, ignoring trailing blank lines.
---@param before? integer Only look at rows before this one
function Converter:last_content_row(node, before)
  local start_row = node:start()
  local end_row, end_col = node:end_()
  if end_col == 0 and end_row > start_row then end_row = end_row - 1 end
  if before then end_row = math.max(math.min(end_row, before - 1), start_row) end
  while end_row > start_row and self:is_blank_row(end_row) do
    end_row = end_row - 1
  end
  return end_row
end

function Converter:blank_between(a, b)
  -- A node may end on the next one's first row, holding its indentation.
  local row = b:start()
  return row > self:last_content_row(a, row) + 1
end

--------------------------------------------------------------------------------
-- Inlines
--------------------------------------------------------------------------------

---@class md_rich_copy.Inline
---@field conv md_rich_copy.Converter
---@field text string
---@field out string[]
local Inline = {}
Inline.__index = Inline

function Inline:sub(s, e)
  return self.text:sub(s + 1, e)
end

--- Emit text[from, to) of node, rendering the children that lie inside it.
function Inline:span(node, from, to)
  local pos = from
  -- Punctuation shows up as anonymous nodes; only named ones are Markdown syntax.
  for child in node:iter_children() do
    local cs, ce = range(child)
    if child:named() and cs >= from and ce <= to then
      table.insert(self.out, text_html(self:sub(pos, cs)))
      self:node(child)
      pos = ce
    end
  end
  table.insert(self.out, text_html(self:sub(pos, to)))
end

function Inline:whole(node)
  self:span(node, range(node))
end

--- Emit the content of an emphasis-like node between its n-character delimiters.
function Inline:between_delimiters(node, n)
  local s, e = range(node)
  self:span(node, s + n, e - n)
end

--- The plain (unescaped) text of node, for alt attributes.
function Inline:plain(node)
  local saved = self.out
  self.out = {}
  self:whole(node)
  local html = table.concat(self.out)
  self.out = saved
  return (html:gsub("<[^>]*>", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

function Inline:link(node, href, title)
  local text = child_of_type(node, "link_text")
  local title_attr = title and (' title="%s"'):format(escape_attr(title)) or ""
  table.insert(self.out, ('<a href="%s"%s>'):format(escape_attr(href), title_attr))
  if text then self:whole(text) end
  table.insert(self.out, "</a>")
end

local function destination(inline, node)
  local dest = child_of_type(node, "link_destination")
  if not dest then return "" end
  return unescape_punct((inline:sub(range(dest)):gsub("^<(.*)>$", "%1")))
end

local function title_of(inline, node)
  local title = child_of_type(node, "link_title")
  return title and unescape_punct(inline:sub(range(title)):sub(2, -2)) or nil
end

function Inline:node(node)
  local type = node:type()
  if type == "emphasis" then
    table.insert(self.out, "<em>")
    self:between_delimiters(node, 1)
    table.insert(self.out, "</em>")
  elseif type == "strong_emphasis" then
    table.insert(self.out, "<strong>")
    self:between_delimiters(node, 2)
    table.insert(self.out, "</strong>")
  elseif type == "strikethrough" then
    -- The parser reads "~~x~~" as a single-tilde strikethrough nested in another.
    local s, e = range(node)
    local inner = node:named_child_count() == 3 and node:named_child(1)
    if inner and inner:type() == "strikethrough" then
      local is, ie = range(inner)
      if is == s + 1 and ie == e - 1 then node = inner end
    end
    -- Jira reads only <del>, Slack reads only <s>.
    table.insert(self.out, "<del><s>")
    self:between_delimiters(node, 1)
    table.insert(self.out, "</s></del>")
  elseif type == "code_span" then
    local first, last = node:named_child(0), node:named_child(node:named_child_count() - 1)
    local _, s = range(first)
    local e = range(last)
    local code = self:sub(s, e):gsub("\n", " ")
    if code:match "^ .* $" and code:match "[^ ]" then code = code:sub(2, -2) end
    table.insert(self.out, "<code>" .. escape(code) .. "</code>")
  elseif type == "inline_link" then
    self:link(node, destination(self, node), title_of(self, node))
  elseif type == "full_reference_link" or type == "collapsed_reference_link" or type == "shortcut_link" then
    local label = child_of_type(node, "link_label") or child_of_type(node, "link_text")
    local ref = label and self.conv.refs[link_label(self:sub(range(label)))]
    if ref then
      self:link(node, ref.href, ref.title)
    else
      self:whole(node)
    end
  elseif type == "image" then
    local desc = child_of_type(node, "image_description")
    local title = title_of(self, node)
    table.insert(
      self.out,
      ('<img src="%s" alt="%s"%s />'):format(
        escape_attr(destination(self, node)),
        escape_attr(desc and self:plain(desc) or ""),
        title and (' title="%s"'):format(escape_attr(title)) or ""
      )
    )
  elseif type == "uri_autolink" or type == "email_autolink" then
    local target = self:sub(range(node)):sub(2, -2)
    local href = type == "email_autolink" and "mailto:" .. target or target
    table.insert(self.out, ('<a href="%s">%s</a>'):format(escape_attr(href), escape(target)))
  elseif type == "backslash_escape" then
    table.insert(self.out, escape(self:sub(range(node)):sub(2)))
  elseif type == "hard_line_break" then
    table.insert(self.out, "<br />\n")
  elseif type == "entity_reference" or type == "numeric_character_reference" or type == "html_tag" then
    table.insert(self.out, self:sub(range(node)))
  else
    self:whole(node)
  end
end

--- Render inline Markdown text to HTML.
function Converter:inline(text)
  if text == "" then return "" end
  local inline = setmetatable({ conv = self, text = text, out = {} }, Inline)
  inline:whole(parse(text, "markdown_inline"))
  return table.concat(inline.out)
end

--- Render the content of an inline or table cell node of the block tree.
function Converter:inline_node(node)
  if not node then return "" end
  -- Continuation lines lose their leading spaces, like CommonMark does.
  local text = self:strip_continuations(node):gsub("\n[ \t]+", "\n")
  return self:inline(vim.trim(text))
end

--------------------------------------------------------------------------------
-- Blocks
--------------------------------------------------------------------------------

local SKIP = {
  block_continuation = true,
  block_quote_marker = true,
  link_reference_definition = true,
  minus_metadata = true,
  plus_metadata = true,
}

local function is_marker(type)
  return type:match "^list_marker_" or type:match "^task_list_marker_"
end

--- The block children of a container, without markers and continuations.
local function block_children(node)
  local children = {}
  for child in node:iter_children() do
    local type = child:type()
    if child:named() and not SKIP[type] and not is_marker(type) then table.insert(children, child) end
  end
  return children
end

--- A list is loose when its items, or two blocks directly inside an item, are
--- separated by a blank line. Items of a tight list render without <p>.
function Converter:is_loose(list)
  local items = block_children(list)
  for i, item in ipairs(items) do
    if items[i + 1] and self:blank_between(item, items[i + 1]) then return true end
    local blocks = block_children(item)
    for j = 1, #blocks - 1 do
      if self:blank_between(blocks[j], blocks[j + 1]) then return true end
    end
  end
  return false
end

function Converter:blocks(node, opts)
  local out = {}
  for _, child in ipairs(block_children(node)) do
    local html = self:block(child, opts)
    if html then table.insert(out, html) end
    opts = opts and { tight = opts.tight }
  end
  return table.concat(out, "\n")
end

function Converter:fenced_code_block(node)
  local content = child_of_type(node, "code_fence_content")
  if not content then return code_block "" end
  -- Content lines lose as many leading spaces as the opening fence is indented.
  local indent = #self:text(child_of_type(node, "fenced_code_block_delimiter")):match "^ *"
  local lines = vim.split(self:strip_continuations(content):gsub("\n$", ""), "\n", { plain = true })
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("^" .. (" ?"):rep(indent), "", 1)
  end
  return code_block(table.concat(lines, "\n"))
end

function Converter:indented_code_block(node)
  -- The parser is inconsistent about whether a line's continuation covers the
  -- 4-space indentation, so cut the container prefix (the continuation, if any)
  -- and then strip spaces up to the column where the first line's code starts.
  local start_row, start_col = node:start()
  local base = start_col + #self.lines[start_row + 1]:sub(start_col + 1):match "^ ? ? ? ?"
  local lines = {}
  for row = start_row, self:last_content_row(node) do
    local cut = row == start_row and start_col or self.continuation_end[row] or 0
    local rest = self.lines[row + 1]:sub(cut + 1)
    table.insert(lines, (rest:gsub("^" .. (" ?"):rep(math.max(base - cut, 0)), "", 1)))
  end
  return code_block(table.concat(lines, "\n"))
end

function Converter:list(node)
  local items = block_children(node)
  local marker = child_of_type(items[1], "list_marker_dot") or child_of_type(items[1], "list_marker_parenthesis")
  local tag, open = "ul", "<ul>"
  if marker then
    tag, open = "ol", "<ol>"
    local start = tonumber(self:text(marker):match "%d+")
    if start ~= 1 then open = ('<ol start="%d">'):format(start) end
  end
  local tight = not self:is_loose(node)
  local out = { open }
  for _, item in ipairs(items) do
    -- <input> checkboxes vanish in Confluence, Jira and Slack; use characters.
    local prefix = child_of_type(item, "task_list_marker_checked") and "☑ "
      or child_of_type(item, "task_list_marker_unchecked") and "☐ "
      or nil
    table.insert(out, "<li>" .. self:blocks(item, { tight = tight, prefix = prefix }) .. "</li>")
  end
  table.insert(out, ("</%s>"):format(tag))
  return table.concat(out, "\n")
end

function Converter:table(node)
  local align = {}
  local delimiter = child_of_type(node, "pipe_table_delimiter_row")
  for cell in delimiter:iter_children() do
    if cell:type() == "pipe_table_delimiter_cell" then
      local left = child_of_type(cell, "pipe_table_align_left")
      local right = child_of_type(cell, "pipe_table_align_right")
      table.insert(align, left and right and "center" or left and "left" or right and "right" or false)
    end
  end
  local function row(row_node, tag)
    local cells = {}
    for cell in row_node:iter_children() do
      if cell:type() == "pipe_table_cell" then table.insert(cells, cell) end
    end
    local out = { "<tr>" }
    for i = 1, #align do
      local style = CELL_STYLE .. (align[i] and (" text-align: %s;"):format(align[i]) or "")
      table.insert(out, ('<%s style="%s">%s</%s>'):format(tag, style, self:inline_node(cells[i]), tag))
    end
    table.insert(out, "</tr>")
    return table.concat(out, "\n")
  end
  local out = { ('<table style="%s">'):format(TABLE_STYLE), "<thead>" }
  table.insert(out, row(child_of_type(node, "pipe_table_header"), "th"))
  table.insert(out, "</thead>")
  local body = {}
  for child in node:iter_children() do
    if child:type() == "pipe_table_row" then table.insert(body, row(child, "td")) end
  end
  if #body > 0 then
    table.insert(out, "<tbody>")
    vim.list_extend(out, body)
    table.insert(out, "</tbody>")
  end
  table.insert(out, "</table>")
  return table.concat(out, "\n")
end

---@param opts? {tight: boolean?, prefix: string?}
function Converter:block(node, opts)
  opts = opts or {}
  local type = node:type()
  if type == "document" or type == "section" then
    return self:blocks(node)
  elseif type == "atx_heading" then
    local level = node:named_child(0):type():match "^atx_h(%d)_marker$"
    local content = child_of_type(node, "inline")
    -- The optional closing sequence ("## Title ##") is not part of the title.
    local text = content and vim.trim(self:strip_continuations(content)):gsub("^#+$", ""):gsub("%s+#+$", "") or ""
    return ("<h%s>%s</h%s>"):format(level, self:inline(text), level)
  elseif type == "setext_heading" then
    local level = child_of_type(node, "setext_h1_underline") and 1 or 2
    local paragraph = child_of_type(node, "paragraph")
    local content = paragraph and self:inline_node(child_of_type(paragraph, "inline")) or ""
    return ("<h%d>%s</h%d>"):format(level, content, level)
  elseif type == "paragraph" then
    local content = (opts.prefix or "") .. self:inline_node(child_of_type(node, "inline"))
    return opts.tight and content or "<p>" .. content .. "</p>"
  elseif type == "block_quote" then
    return ('<blockquote style="%s">\n%s\n</blockquote>'):format(QUOTE_STYLE, self:blocks(node))
  elseif type == "list" then
    return self:list(node)
  elseif type == "fenced_code_block" then
    return self:fenced_code_block(node)
  elseif type == "indented_code_block" then
    return self:indented_code_block(node)
  elseif type == "thematic_break" then
    return "<hr />"
  elseif type == "html_block" then
    return (self:strip_continuations(node):gsub("\n+$", ""))
  elseif type == "pipe_table" then
    return self:table(node)
  else
    -- Anything the parser could not make sense of is kept as text.
    return "<p>" .. escape(vim.trim(self:text(node))) .. "</p>"
  end
end

--- Collect link reference definitions, so that reference links can be resolved,
--- and where the continuation of each line ends.
function Converter:collect(node)
  for child in node:iter_children() do
    if child:type() == "block_continuation" then
      local row, col = child:end_()
      self.continuation_end[row] = math.max(self.continuation_end[row] or 0, col)
    elseif child:type() == "link_reference_definition" then
      local label = child_of_type(child, "link_label")
      local dest = child_of_type(child, "link_destination")
      local title = child_of_type(child, "link_title")
      local key = label and link_label(self:text(label))
      if key and dest and not self.refs[key] then
        self.refs[key] = {
          href = unescape_punct((self:text(dest):gsub("^<(.*)>$", "%1"))),
          title = title and unescape_punct(self:text(title):sub(2, -2)) or nil,
        }
      end
    elseif child:named_child_count() > 0 then
      self:collect(child)
    end
  end
end

--- Convert Markdown to HTML adjusted for pasting.
---@param markdown string
---@return string
function M.convert(markdown)
  local src = markdown:gsub("\r\n?", "\n")
  if not src:match "\n$" then src = src .. "\n" end
  local conv = setmetatable({
    src = src,
    lines = vim.split(src, "\n", { plain = true }),
    refs = {},
    continuation_end = {},
  }, Converter)
  local root = parse(src, "markdown")
  conv:collect(root)
  local html = conv:block(root)
  return html == "" and "" or html .. "\n"
end

return M
