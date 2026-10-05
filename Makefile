SHELL := /bin/bash
SCRIPTS := $(wildcard scripts/*.sh) tests/run.sh
PREFIX ?= /usr/local

.PHONY: all lint test install uninstall

all: lint test

lint: ## Статический анализ shellcheck
	shellcheck -x $(SCRIPTS)

test: ## Дымовые тесты
	bash tests/run.sh

install: ## Установка в $(PREFIX)/lib/linux-admin-scripts и симлинки в $(PREFIX)/bin
	install -d $(PREFIX)/lib/linux-admin-scripts $(PREFIX)/bin
	install -m 0755 scripts/*.sh $(PREFIX)/lib/linux-admin-scripts/
	for f in scripts/*.sh; do \
		name=$$(basename $$f .sh); \
		[ "$$name" = lib ] && continue; \
		ln -sf $(PREFIX)/lib/linux-admin-scripts/$$name.sh $(PREFIX)/bin/$$name.sh; \
	done

uninstall: ## Удалить установленные файлы
	for f in scripts/*.sh; do rm -f $(PREFIX)/bin/$$(basename $$f); done
	rm -rf $(PREFIX)/lib/linux-admin-scripts
