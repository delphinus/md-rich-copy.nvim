# md-rich-copy.nvim

[日本語版はこちら / Japanese version](README.ja.md)

Copy Markdown from Neovim to the macOS clipboard as rich text, so that pasting it into Mail.app, Confluence, Jira or Slack gives formatted text instead of raw markup.

## How it works

1. The tree-sitter parsers `markdown` and `markdown_inline`, bundled with Neovim, parse the Markdown (GitHub Flavored Markdown: tables, task lists, strikethrough and bare URLs included).
2. The plugin writes HTML from the syntax tree, adjusted for the paste targets (see below). No external converter is needed.
3. The HTML and the original Markdown (as plain text) are put on the clipboard together.

The adjustments come from pasting the same document into each target and fixing what broke:

| Element | Adjustment | Why |
|---|---|---|
| Task lists | `<input>` checkboxes become `☐` / `☑` | Checkboxes vanish in Confluence, Jira and Slack |
| Strikethrough | Wrapped in both `<del>` and `<s>` | Jira reads only `<del>`, Slack reads only `<s>` |
| Code blocks | Newlines become `<br>` | Jira joins the lines of a `<pre>` into one |
| Tables, block quotes | Only borders and a left bar are styled | Mail.app shows neither otherwise; font sizes and colors are left to the target |
| Plain text | The Markdown source is added | Slack refuses to paste when there is no plain-text flavor |

Slack has no headings or tables, so headings paste as plain lines and tables as preformatted text.

The tree-sitter grammar does not follow CommonMark to the letter, so unusual constructs may render differently from GitHub. Everyday documents convert as expected.

## Requirements

- macOS (the clipboard is written through `osascript`)
- Neovim >= 0.10
- The tree-sitter parsers `markdown` and `markdown_inline`. Neovim >= 0.10 bundles them; if [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) has installed its own, those are used instead.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "delphinus/md-rich-copy.nvim", cmd = "MdRichCopy" }
```

No `setup()` call is needed.

## Usage

| Command | Action |
|---|---|
| `:MdRichCopy` | Copy the whole buffer |
| `:'<,'>MdRichCopy` | Copy the selected lines |

To map it to a key:

```lua
vim.keymap.set({ "n", "x" }, "<Leader>y", ":MdRichCopy<CR>", { silent = true })
```

## Lua API

```lua
local rich = require "md-rich-copy"
rich.to_html(markdown) -- Markdown string -> adjusted HTML string
rich.copy(lines)       -- copy a list of lines to the clipboard
```

## Development

```sh
make test   # run the tests (tests/*_test.lua) with the parsers bundled with Neovim
make lint   # check formatting with StyLua
```

`tests/clipboard_test.lua` overwrites the clipboard, so it runs only when `MD_RICH_COPY_TEST_CLIPBOARD=1` is set. CI sets it on a macOS runner.

Releases are cut by [release-please](https://github.com/googleapis/release-please): merging Conventional Commits into `main` keeps a release PR up to date, and merging that PR tags the version and publishes the GitHub release.

## License

MIT
