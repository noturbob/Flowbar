PREFIX ?= $(HOME)/.local
VALAC  ?= valac

# gtk4-layer-shell must come before gtk4 so it links ahead of libwayland-client.
flowbar: src/*.vala
	$(VALAC) --pkg gtk4-layer-shell-0 --pkg gtk4 -o $@ $^

install: flowbar
	install -Dm755 flowbar $(PREFIX)/bin/flowbar

clean:
	rm -f flowbar

.PHONY: install clean
