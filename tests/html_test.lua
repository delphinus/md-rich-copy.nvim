-- Test the Markdown to HTML conversion in lua/md-rich-copy/html.lua
-- Run: nvim --headless -u NONE --noplugin -l tests/html_test.lua

local H = require "tests.helper"
local convert = require("md-rich-copy.html").convert

local CELL = "border:1px solid #999; padding:4px 8px;"
local QUOTE = '<blockquote style="border-left:3px solid #ccc; margin-left:0; padding-left:12px;">'

--- Convert lines of Markdown and compare with lines of HTML.
local function check(name, markdown, html)
  H.test(name, function()
    H.eq(convert(table.concat(markdown, "\n")), table.concat(html, "\n") .. "\n", name)
  end)
end

--- Convert a single line and compare the inline HTML inside <p>.
local function inline(name, markdown, html)
  check(name, { markdown }, { "<p>" .. html .. "</p>" })
end

H.test("empty input gives empty output", function()
  H.eq(convert "", "", "empty")
  H.eq(convert "\n\n", "", "blank lines")
end)

-- Headings

check("ATX headings", { "# One", "###### Six" }, { "<h1>One</h1>", "<h6>Six</h6>" })
check("closing sequence of an ATX heading is dropped", { "## Title ##" }, { "<h2>Title</h2>" })
check("empty ATX heading", { "#" }, { "<h1></h1>" })
check("setext headings", { "One", "===", "", "Two", "---" }, { "<h1>One</h1>", "<h2>Two</h2>" })
check("inline markup in a heading", { "# A *b*" }, { "<h1>A <em>b</em></h1>" })

-- Paragraphs and line breaks

check("paragraphs", { "a", "", "b" }, { "<p>a</p>", "<p>b</p>" })
check("soft line break keeps the newline", { "a", "b" }, { "<p>a", "b</p>" })
check("hard line breaks", { "a  ", "b\\", "c" }, { "<p>a<br />", "b<br />", "c</p>" })
check("indentation of continuation lines is dropped", { "a", "   b" }, { "<p>a", "b</p>" })
check("CRLF line endings", { "a\r", "b\r" }, { "<p>a", "b</p>" })

-- Inlines

inline("emphasis and strong", "*a* _b_ **c** __d__", "<em>a</em> <em>b</em> <strong>c</strong> <strong>d</strong>")
inline("nested emphasis", "***a*** *b **c** d*", "<em><strong>a</strong></em> <em>b <strong>c</strong> d</em>")
inline("underscores inside a word stay", "snake_case_word", "snake_case_word")
-- Jira reads only <del>, Slack reads only <s>.
inline("strikethrough is wrapped in both del and s", "~~a~~", "<del><s>a</s></del>")
inline("single-tilde strikethrough", "~a~", "<del><s>a</s></del>")
inline("code span is escaped", "`a < b & c`", "<code>a &lt; b &amp; c</code>")
inline("code span with backticks inside", "`` a`b ``", "<code>a`b</code>")
inline("code span keeps inner spaces when all spaces", "` `", "<code> </code>")
inline("text is escaped", "a < b & c > d", "a &lt; b &amp; c &gt; d")
inline("backslash escapes", "\\*a\\* \\<b\\>", "*a* &lt;b&gt;")
inline("entities pass through", "&copy; &#169;", "&copy; &#169;")
inline("inline HTML passes through", "<kbd>K</kbd>", "<kbd>K</kbd>")
inline(
  "Japanese text",
  "日本語の**強調**と`コード`",
  "日本語の<strong>強調</strong>と<code>コード</code>"
)

-- Links and images

inline("inline link", "[a *b*](https://example.com/x)", '<a href="https://example.com/x">a <em>b</em></a>')
inline("inline link with title", '[a](https://e.example "T")', '<a href="https://e.example" title="T">a</a>')
inline(
  "link destination is escaped",
  "[a](https://e.example/?x=1&y=2)",
  '<a href="https://e.example/?x=1&amp;y=2">a</a>'
)
inline("angle-bracket destination", "[a](<https://e.example/b>)", '<a href="https://e.example/b">a</a>')
inline("autolink", "<https://e.example>", '<a href="https://e.example">https://e.example</a>')
inline("email autolink", "<me@e.example>", '<a href="mailto:me@e.example">me@e.example</a>')
inline("bare URL", "see https://e.example/a.", 'see <a href="https://e.example/a">https://e.example/a</a>.')
inline("bare www URL", "www.e.example", '<a href="http://www.e.example">www.e.example</a>')
inline(
  "bare URL keeps balanced parentheses",
  "https://e.example/a_(b)",
  '<a href="https://e.example/a_(b)">https://e.example/a_(b)</a>'
)
inline(
  "bare URL drops an unbalanced parenthesis",
  "(https://e.example)",
  '(<a href="https://e.example">https://e.example</a>)'
)
inline(
  "bare URL stops at Japanese text",
  "https://e.example/aを参照",
  '<a href="https://e.example/a">https://e.example/a</a>を参照'
)
inline("image", "![a *b* & c](i.png)", '<img src="i.png" alt="a b &amp; c" />')
check("reference links", {
  "[full][R] [collapsed][] [shortcut]",
  "",
  '[r]: https://r.example "Title"',
  "[collapsed]: https://c.example",
  "[shortcut]: <https://s.example>",
}, {
  '<p><a href="https://r.example" title="Title">full</a> <a href="https://c.example">collapsed</a>'
    .. ' <a href="https://s.example">shortcut</a></p>',
})
inline("undefined reference stays as text", "[a] [b][c]", "[a] [b][c]")

-- Lists

check("tight bullet list", { "- a", "- b" }, { "<ul>", "<li>a</li>", "<li>b</li>", "</ul>" })
check("loose bullet list", { "- a", "", "- b" }, { "<ul>", "<li><p>a</p></li>", "<li><p>b</p></li>", "</ul>" })
check(
  "item with two paragraphs is loose",
  { "- a", "", "  b", "- c" },
  { "<ul>", "<li><p>a</p>", "<p>b</p></li>", "<li><p>c</p></li>", "</ul>" }
)
check("ordered list", { "1. a", "2. b" }, { "<ol>", "<li>a</li>", "<li>b</li>", "</ol>" })
check("ordered list start", { "3) a" }, { '<ol start="3">', "<li>a</li>", "</ol>" })
check("nested lists", { "- a", "  1. b", "- c" }, {
  "<ul>",
  "<li>a",
  "<ol>",
  "<li>b</li>",
  "</ol></li>",
  "<li>c</li>",
  "</ul>",
})
check("a loose nested list keeps the outer list tight", { "- a", "  - b", "", "  - c", "- d" }, {
  "<ul>",
  "<li>a",
  "<ul>",
  "<li><p>b</p></li>",
  "<li><p>c</p></li>",
  "</ul></li>",
  "<li>d</li>",
  "</ul>",
})
-- <input> checkboxes vanish in Confluence, Jira and Slack.
check("task list items become characters", { "- [ ] todo", "- [x] done" }, {
  "<ul>",
  "<li>☐ todo</li>",
  "<li>☑ done</li>",
  "</ul>",
})
check(
  "loose task list",
  { "- [ ] a", "", "- [X] b" },
  { "<ul>", "<li><p>☐ a</p></li>", "<li><p>☑ b</p></li>", "</ul>" }
)

-- Block quotes

check("block quote gets a left bar", { "> a", "> b" }, { QUOTE, "<p>a", "b</p>", "</blockquote>" })
check("lazy continuation in a block quote", { "> a", "b" }, { QUOTE, "<p>a", "b</p>", "</blockquote>" })
check(
  "block quote with a list",
  { "> a", ">", "> - b" },
  { QUOTE, "<p>a</p>", "<ul>", "<li>b</li>", "</ul>", "</blockquote>" }
)

-- Code blocks: Jira joins the lines of a <pre> into one, so they are broken with <br>.

check(
  "fenced code block",
  { "```lua", 'local s = "<a>"', "", "print(s)", "```" },
  { '<pre><code>local s = "&lt;a&gt;"<br><br>print(s)</code></pre>' }
)
check("tilde fence", { "~~~", "a", "~~~" }, { "<pre><code>a</code></pre>" })
check("empty fenced code block", { "```", "```" }, { "<pre><code></code></pre>" })
check(
  "indented fence strips its indentation",
  { "  ```", "  a", "    b", "  ```" },
  { "<pre><code>a<br>  b</code></pre>" }
)
check("fenced code in a list item", { "- a", "", "  ```", "  b", "    c", "  ```" }, {
  "<ul>",
  "<li><p>a</p>",
  "<pre><code>b<br>  c</code></pre></li>",
  "</ul>",
})
check("fenced code in a block quote", { "> ```", "> a", ">   b", "> ```" }, {
  QUOTE,
  "<pre><code>a<br>  b</code></pre>",
  "</blockquote>",
})
check("indented code block", { "    a", "      b", "", "    c" }, { "<pre><code>a<br>  b<br><br>c</code></pre>" })
check("indented code in a list item", { "- a", "", "      b", "        c", "", "      d" }, {
  "<ul>",
  "<li><p>a</p>",
  "<pre><code>b<br>  c<br><br>d</code></pre></li>",
  "</ul>",
})
check(
  "indented code in a block quote",
  { ">     a", ">       b" },
  { QUOTE, "<pre><code>a<br>  b</code></pre>", "</blockquote>" }
)

-- Tables: Mail.app draws no borders without styles.

check("table with alignment", {
  "| L | C | R | N |",
  "|:--|:-:|--:|---|",
  "| a \\| b | **c** | 1 |",
}, {
  '<table style="border-collapse:collapse;">',
  "<thead>",
  "<tr>",
  ('<th style="%s text-align: left;">L</th>'):format(CELL),
  ('<th style="%s text-align: center;">C</th>'):format(CELL),
  ('<th style="%s text-align: right;">R</th>'):format(CELL),
  ('<th style="%s">N</th>'):format(CELL),
  "</tr>",
  "</thead>",
  "<tbody>",
  "<tr>",
  ('<td style="%s text-align: left;">a | b</td>'):format(CELL),
  ('<td style="%s text-align: center;"><strong>c</strong></td>'):format(CELL),
  ('<td style="%s text-align: right;">1</td>'):format(CELL),
  ('<td style="%s"></td>'):format(CELL),
  "</tr>",
  "</tbody>",
  "</table>",
})
check("table without body rows", { "| a |", "|---|" }, {
  '<table style="border-collapse:collapse;">',
  "<thead>",
  "<tr>",
  ('<th style="%s">a</th>'):format(CELL),
  "</tr>",
  "</thead>",
  "</table>",
})

-- Other blocks

check("thematic break", { "a", "", "***", "", "b" }, { "<p>a</p>", "<hr />", "<p>b</p>" })
check("HTML block passes through", { "<div>", "a", "</div>" }, { "<div>", "a", "</div>" })
check("front matter is dropped", { "---", "title: x", "---", "", "a" }, { "<p>a</p>" })

H.finish()
