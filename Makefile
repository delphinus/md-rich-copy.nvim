# Point the XDG directories at an empty place so that only the parsers bundled
# with Neovim are used, not ones nvim-treesitter installed under ~/.local/share.
XDG := $(CURDIR)/.tests/xdg
NVIM_BIN ?= nvim
NVIM := XDG_DATA_HOME=$(XDG)/data XDG_CONFIG_HOME=$(XDG)/config XDG_STATE_HOME=$(XDG)/state \
	$(NVIM_BIN) --headless -u NONE --noplugin

TEST_FILES := $(sort $(wildcard tests/*_test.lua))

.PHONY: test $(TEST_FILES) lint format check

test: $(TEST_FILES)

# tests/clipboard_test.lua overwrites the clipboard, so it skips itself unless
# MD_RICH_COPY_TEST_CLIPBOARD=1 is set (CI does this on macOS).
$(TEST_FILES):
	$(NVIM) -l $@

# Format Lua sources in place (honors .stylua.toml).
format:
	stylua .

# Local gate: formatting check. Luacheck runs in CI (.github/workflows/lint.yml).
lint:
	stylua --check .

check: lint test
