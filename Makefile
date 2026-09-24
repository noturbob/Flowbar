PREFIX ?= $(HOME)/.local
VALAC  ?= valac

# gtk4-layer-shell must come before gtk4 so it links ahead of libwayland-client.
flowbar: src/*.vala
	$(VALAC) --pkg gtk4-layer-shell-0 --pkg gtk4 -o $@ $^

CONFIG ?= $(HOME)/.config/flowbar

install: flowbar
	install -Dm755 flowbar $(PREFIX)/bin/flowbar
	@# Never overwrite a config you've already made your own.
	@test -e $(CONFIG)/config.ini || install -Dm644 config.ini $(CONFIG)/config.ini

# Build and run in the foreground, with warnings (CSS errors, bad config) on stderr.
run: flowbar
	-pkill -x flowbar
	./flowbar

clean:
	rm -f flowbar

.PHONY: install run clean
