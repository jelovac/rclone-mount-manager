SHELL := /usr/bin/env bash

PROJECT_FILES := \
	bin/rclone-mount-manager \
	install.sh \
	uninstall.sh \
	tests/test.sh

.PHONY: test syntax lint format-check

test: syntax
	bash tests/test.sh

syntax:
	bash -n $(PROJECT_FILES)

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(PROJECT_FILES); \
	else \
		echo "shellcheck not installed; skipping"; \
	fi

format-check:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d $(PROJECT_FILES); \
	else \
		echo "shfmt not installed; skipping"; \
	fi
