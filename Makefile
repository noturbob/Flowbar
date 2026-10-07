PREFIX ?= $(HOME)/.local
# valac makes and removes its own C files; make's built-in rules would trip over leftovers.
MAKEFLAGS += --no-builtin-rules
VALAC  ?= valac

PROTOCOL = $(shell pkg-config --variable=pkgdatadir wayland-protocols)/staging/ext-background-effect/ext-background-effect-v1.xml
GENERATED = src/ext-background-effect-v1-client-protocol.h src/ext-background-effect-v1-protocol.c

# gtk4-layer-shell must come before gtk4 so it links ahead of libwayland-client.
flowbar: src/*.vala src/blur.c $(GENERATED)
	$(VALAC) --pkg gtk4-layer-shell-0 --pkg gtk4 --pkg json-glib-1.0 -X -lm -X -lwayland-client -o $@ \
		src/*.vala src/blur.c src/ext-background-effect-v1-protocol.c

src/ext-background-effect-v1-client-protocol.h: $(PROTOCOL)
	wayland-scanner client-header $< $@

src/ext-background-effect-v1-protocol.c: $(PROTOCOL)
	wayland-scanner private-code $< $@

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
	rm -f flowbar $(GENERATED)

.PHONY: install run clean
