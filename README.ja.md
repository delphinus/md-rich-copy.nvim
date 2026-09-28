# md-rich-copy.nvim

[English version / 英語版はこちら](README.md)

Neovim で書いた Markdown を、macOS のクリップボードにリッチテキストとしてコピーします。メール.app・Confluence・Jira・Slack に貼り付けると、Markdown の記号ではなく書式付きの文章になります。

## 仕組み

1. Neovim に同梱されている tree-sitter のパーサー `markdown` と `markdown_inline` で Markdown (GitHub Flavored Markdown。表・タスクリスト・取り消し線・URL の自動リンクを含む) を解析します。
2. 構文木から、貼り付け先に合わせて手直しした HTML を書き出します (下表)。外部の変換ツールは要りません。
3. HTML と、元の Markdown (プレーンテキスト) を一緒にクリップボードへ入れます。

手直しの内容は、同じ文書を各貼り付け先に貼って、崩れたところを直した結果です。

| 要素 | 手直し | 理由 |
|---|---|---|
| タスクリスト | `<input>` のチェックボックスを絵文字の `✅` / `⬜` にする | Confluence・Jira・Slack ではチェックボックスが消える。`☐` / `☑` のような記号の文字は、描くフォントによって大きさがそろわない |
| 取り消し線 | `<del>` と `<s>` の両方で囲む | Jira は `<del>`、Slack は `<s>` しか読まない |
| コードブロック | 改行を `<br>` に、行頭と連続する空白を `&nbsp;` にする | Jira は `<pre>` の中の行を 1 行につなげ、空白も詰めてしまう |
| 表・引用 | 罫線と左端の線だけを付ける | メール.app ではどちらも出ない。文字の大きさや色は貼り付け先に任せる |
| プレーンテキスト | Markdown の原文を入れる | Slack はプレーンテキストが無いと貼り付けを受け付けない |

Slack には見出しと表の書式が無いので、見出しは普通の行、表は整形済みテキストとして貼られます。

tree-sitter の文法は CommonMark に厳密には従っていないため、珍しい書き方では GitHub と表示が異なることがあります。普段の文書は問題なく変換できます。

## 必要なもの

- macOS (`osascript` でクリップボードに書き込みます)
- Neovim 0.10 以降
- tree-sitter のパーサー `markdown` と `markdown_inline`。Neovim 0.10 以降に同梱されています。[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) で入れたものがあれば、そちらが使われます。

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim) の場合:

```lua
{ "delphinus/md-rich-copy.nvim", cmd = "MdRichCopy" }
```

`setup()` を呼ぶ必要はありません。

## 使い方

| コマンド | 動作 |
|---|---|
| `:MdRichCopy` | バッファ全体をコピーする |
| `:'<,'>MdRichCopy` | 選択した行をコピーする |

キーに割り当てる例:

```lua
vim.keymap.set({ "n", "x" }, "<Leader>y", ":MdRichCopy<CR>", { silent = true })
```

## Lua API

```lua
local rich = require "md-rich-copy"
rich.to_html(markdown) -- Markdown の文字列 -> 手直し済みの HTML の文字列
rich.copy(lines)       -- 行のリストをクリップボードへコピーする
```

## 開発

```sh
make test   # テスト (tests/*_test.lua) を Neovim 同梱のパーサーで実行する
make lint   # StyLua で書式を確認する
```

`tests/clipboard_test.lua` はクリップボードを上書きするので、`MD_RICH_COPY_TEST_CLIPBOARD=1` を設定したときだけ実行されます。CI では macOS のランナーで設定しています。

リリースは [release-please](https://github.com/googleapis/release-please) で行います。Conventional Commits を `main` にマージするとリリース PR が更新され、その PR をマージするとタグが付いて GitHub のリリースが公開されます。

## ライセンス

MIT
