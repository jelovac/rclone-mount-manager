SHELL := /usr/bin/env bash

PROJECT_FILES := \
	bin/rclone-mount-manager \
	install.sh \
	uninstall.sh \
	tests/test.sh

GNOME_EXTENSION_DIR := gnome-extension/rclone-mount-manager@jelovac.net

.PHONY: test syntax lint format-check

test: syntax
	bash tests/test.sh

syntax:
	bash -n $(PROJECT_FILES)
	@if command -v python3 >/dev/null 2>&1; then \
		python3 -m json.tool $(GNOME_EXTENSION_DIR)/metadata.json >/dev/null; \
	else \
		echo "python3 not installed; skipping metadata validation"; \
	fi
	@if command -v gjs >/dev/null 2>&1; then \
		gjs -c "const GLib=imports.gi.GLib; const [ok, bytes]=GLib.file_get_contents('$(GNOME_EXTENSION_DIR)/extension.js'); if (!ok) throw new Error('read failed'); Reflect.parse(new TextDecoder().decode(bytes), {source: 'extension.js', target: 'module'});"; \
	else \
		echo "gjs not installed; skipping GNOME extension syntax validation"; \
	fi

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(PROJECT_FILES); \
	else \
		echo "shellcheck not installed; skipping"; \
	fi

format-check:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d -i 2 -ci $(PROJECT_FILES); \
	else \
		echo "shfmt not installed; skipping"; \
	fi
