# md-rich-copy.nvim

[English version / 英語版はこちら](README.md)

Neovim で書いた Markdown を、macOS のクリップボードにリッチテキストとしてコピーします。メール.app・Confluence・Jira・Slack に貼り付けると、Markdown の記号ではなく書式付きの文章になります。

## 仕組み

1. [pandoc](https://pandoc.org/) で Markdown (GitHub Flavored Markdown) を HTML に変換します。
2. 貼り付け先に合わせて HTML を手直しします (下表)。
3. HTML と、元の Markdown (プレーンテキスト) を一緒にクリップボードへ入れます。

手直しの内容は、同じ文書を各貼り付け先に貼って、崩れたところを直した結果です。

| 要素 | 手直し | 理由 |
|---|---|---|
| タスクリスト | `<input>` のチェックボックスを `☐` / `☑` の文字にする | Confluence・Jira・Slack ではチェックボックスが消える |
| 取り消し線 | `<del>` と `<s>` の両方で囲む | Jira は `<del>`、Slack は `<s>` しか読まない |
| コードブロック | 改行を `<br>` にする | Jira は `<pre>` の中の行を 1 行につなげてしまう |
| 表・引用 | 罫線と左端の線だけを付ける | メール.app ではどちらも出ない。文字の大きさや色は貼り付け先に任せる |
| プレーンテキスト | Markdown の原文を入れる | Slack はプレーンテキストが無いと貼り付けを受け付けない |

Slack には見出しと表の書式が無いので、見出しは普通の行、表は整形済みテキストとして貼られます。

## 必要なもの

- macOS (`osascript` でクリップボードに書き込みます)
- Neovim 0.10 以降
- `$PATH` 上の [pandoc](https://pandoc.org/installing.html)

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

## ライセンス

MIT
