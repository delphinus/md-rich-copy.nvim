-- Convert Markdown to HTML and put it on the macOS clipboard as rich text.
--
-- The conversion lives in md-rich-copy/html.lua; this module handles the clipboard.
local M = {}

local META = [[<meta http-equiv="Content-Type" content="text/html; charset=utf-8">]]

-- Put both HTML and plain text on the pasteboard. Slack refuses to paste at all
-- when there is no plain-text flavor, even though it reads the HTML one.
--
-- With local images, the HTML embeds them as data: URLs for targets in browsers,
-- and a web archive carries them for WebKit apps like Mail.app, which prefer it
-- to HTML and turn its images into attachments. Arguments after the third come
-- in threes: URL, MIME type and file of each image.
local SET_CLIPBOARD = [[
use framework "AppKit"
on run argv
  set ca to current application
  set pb to ca's NSPasteboard's generalPasteboard()
  pb's clearContents()
  set h to (ca's NSData's dataWithContentsOfFile:(item 1 of argv))
  pb's setData:h forType:(ca's NSPasteboardTypeHTML)
  set t to (ca's NSString's stringWithContentsOfFile:(item 2 of argv) encoding:4 |error|:(missing value))
  pb's setString:t forType:(ca's NSPasteboardTypeString)
  if (count of argv) < 4 then return
  set subs to ca's NSMutableArray's new()
  repeat with i from 4 to (count of argv) by 3
    set d to (ca's NSData's dataWithContentsOfFile:(item (i + 2) of argv))
    set keys to {"WebResourceData", "WebResourceMIMEType", "WebResourceURL"}
    (subs's addObject:(ca's NSDictionary's dictionaryWithObjects:{d, item (i + 1) of argv, item i of argv} forKeys:keys))
  end repeat
  set a to (ca's NSData's dataWithContentsOfFile:(item 3 of argv))
  set keys to {"WebResourceData", "WebResourceMIMEType", "WebResourceTextEncodingName", "WebResourceURL", "WebResourceFrameName"}
  set main to (ca's NSDictionary's dictionaryWithObjects:{a, "text/html", "UTF-8", "about:blank", ""} forKeys:keys)
  set archive to (ca's NSDictionary's dictionaryWithObjects:{main, subs} forKeys:{"WebMainResource", "WebSubresources"})
  set plist to (ca's NSPropertyListSerialization's dataWithPropertyList:archive format:(ca's NSPropertyListBinaryFormat_v1_0) options:0 |error|:(missing value))
  pb's setData:plist forType:"com.apple.webarchive"
end run
]]

local MIME = {
  avif = "image/avif",
  bmp = "image/bmp",
  gif = "image/gif",
  jpeg = "image/jpeg",
  jpg = "image/jpeg",
  png = "image/png",
  svg = "image/svg+xml",
  webp = "image/webp",
}

local function url_encode(path)
  return (path:gsub("[^%w%-%._~/]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local function is_file(path)
  return vim.uv.fs_stat(path) ~= nil and vim.fn.isdirectory(path) == 0
end

--- The nearest directory at or above dir that is an Obsidian vault.
local function vault_root(dir)
  local marker = vim.fs.find(".obsidian", { path = dir, upward = true, type = "directory", limit = 1 })[1]
  return marker and vim.fs.dirname(marker)
end

--- Find the file of an image source, or nil when it is remote or missing.
--- Relative paths are looked up from base, and embeds ("![[x.png]]") also in the
--- vault containing base, where Obsidian finds them by name alone.
---@param src string
---@param embed boolean
---@param base string
---@return string?
local function find_image(src, embed, base)
  if not embed then
    if src:match "^file://" then
      src = url_decode(src:gsub("^file://[^/]*", ""))
    elseif src:match "^%a[%w+.-]*:" then
      return
    else
      src = url_decode(src)
    end
  end
  if src:sub(1, 1) == "/" then return is_file(src) and src or nil end
  local candidate = vim.fs.joinpath(base, src)
  if is_file(candidate) then return vim.fs.normalize(candidate) end
  if not embed then return end
  local vault = vault_root(base)
  if not vault then return end
  candidate = vim.fs.joinpath(vault, src)
  if is_file(candidate) then return candidate end
  local name = vim.fs.basename(src)
  return vim.fs.find(function(found, dir)
    return found == name and (dir .. "/" .. found):sub(-#src - 1) == "/" .. src
  end, { path = vault, type = "file", limit = 1 })[1]
end

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read "*a"
  f:close()
  return data
end

--- Convert Markdown to HTML adjusted for pasting.
---@param markdown string
---@param opts? md_rich_copy.ConvertOpts
---@return string
function M.to_html(markdown, opts)
  return require("md-rich-copy.html").convert(markdown, opts)
end

---@class md_rich_copy.CopyOpts
---@field base? string Directory that relative image paths are looked up from (default: the current directory)

--- Copy Markdown lines to the clipboard as rich text, with the source as plain text.
---@param lines string[]
---@param opts? md_rich_copy.CopyOpts
function M.copy(lines, opts)
  local base = opts and opts.base or vim.fn.getcwd()
  local images, order = {}, {}
  local body = M.to_html(table.concat(lines, "\n"), {
    image = function(src, embed)
      local path = find_image(src, embed, base)
      local mime = path and MIME[(path:match "%.(%w+)$" or ""):lower()]
      if not mime then return src end
      local url = "file://" .. url_encode(path)
      if not images[url] then
        images[url] = { path = path, mime = mime }
        table.insert(order, url)
      end
      return url
    end,
  })
  local html = META .. "\n" .. body
  local files = { vim.fn.tempname(), vim.fn.tempname() }
  local args = { "osascript", "-", files[1], files[2] }
  if #order > 0 then
    local archive_file = vim.fn.tempname()
    table.insert(files, archive_file)
    vim.fn.writefile(vim.split(html, "\n"), archive_file, "b")
    table.insert(args, archive_file)
    for _, url in ipairs(order) do
      local image = images[url]
      local data_url = ("data:%s;base64,%s"):format(image.mime, vim.base64.encode(read_file(image.path)))
      html = html:gsub(vim.pesc(('src="%s"'):format(url)), function()
        return ('src="%s"'):format(data_url)
      end)
      vim.list_extend(args, { url, image.mime, image.path })
    end
  end
  vim.fn.writefile(vim.split(html, "\n"), files[1], "b")
  vim.fn.writefile(lines, files[2], "b")
  local ok, result = pcall(function()
    return vim.system(args, { stdin = SET_CLIPBOARD }):wait()
  end)
  for _, file in ipairs(files) do
    vim.fn.delete(file)
  end
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
  local name = vim.api.nvim_buf_get_name(0)
  local base = name ~= "" and vim.fs.dirname(vim.fn.fnamemodify(name, ":p")) or nil
  local ok, err = pcall(M.copy, lines, { base = base })
  if ok then
    vim.notify(("md-rich-copy: copied %d lines as rich text"):format(#lines))
  else
    vim.notify("md-rich-copy: " .. err, vim.log.levels.ERROR)
  end
end

return M
