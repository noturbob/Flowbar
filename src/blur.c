// Background blur behind exactly the bar and its panel, via the ext-background-effect Wayland
// protocol (niri has it; GTK doesn't speak it yet). A compositor-side blur rule can't do this:
// it would blur the whole full-width layer surface, empty space included.
#include <string.h>
#include <gtk/gtk.h>
#include <gdk/wayland/gdkwayland.h>
#include "ext-background-effect-v1-client-protocol.h"

static struct ext_background_effect_manager_v1 *manager = NULL;
static gboolean looked = FALSE;

static void on_global (void *data, struct wl_registry *registry, uint32_t name, const char *iface, uint32_t version) {
    if (strcmp (iface, ext_background_effect_manager_v1_interface.name) == 0)
        manager = wl_registry_bind (registry, name, &ext_background_effect_manager_v1_interface, 1);
}

static void on_global_remove (void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener listener = { on_global, on_global_remove };

// Find the protocol once, on a private queue so GDK's own events aren't dispatched here.
static void look_up (struct wl_display *display) {
    looked = TRUE;
    struct wl_event_queue *queue = wl_display_create_queue (display);
    struct wl_display *wrapped = wl_proxy_create_wrapper (display);
    wl_proxy_set_queue ((struct wl_proxy *) wrapped, queue);
    struct wl_registry *registry = wl_display_get_registry (wrapped);
    wl_registry_add_listener (registry, &listener, NULL);
    wl_display_roundtrip_queue (display, queue);
    wl_registry_destroy (registry);
    wl_proxy_wrapper_destroy (wrapped);
    // The manager stays on this queue; it only sends a capabilities event we don't need.
}

static void forget (gpointer effect) {
    ext_background_effect_surface_v1_destroy (effect);
}

// Blur behind these rectangles of the window: x, y, w, h quads in surface coordinates.
// No rectangles: no blur. Applied with the window's next frame.
void flowbar_blur (GtkWidget *window, int *rects, int n) {
    GdkSurface *surface = gtk_native_get_surface (GTK_NATIVE (window));
    if (surface == NULL || !GDK_IS_WAYLAND_SURFACE (surface))
        return;
    GdkDisplay *display = gdk_surface_get_display (surface);
    if (!looked)
        look_up (gdk_wayland_display_get_wl_display (display));
    if (manager == NULL)
        return; // the compositor can't blur

    struct ext_background_effect_surface_v1 *effect = g_object_get_data (G_OBJECT (surface), "flowbar-blur");
    if (effect == NULL) {
        effect = ext_background_effect_manager_v1_get_background_effect (
            manager, gdk_wayland_surface_get_wl_surface (surface));
        g_object_set_data_full (G_OBJECT (surface), "flowbar-blur", effect, forget);
    }
    struct wl_region *region = NULL;
    if (n >= 4) {
        region = wl_compositor_create_region (gdk_wayland_display_get_wl_compositor (display));
        for (int i = 0; i + 3 < n; i += 4)
            wl_region_add (region, rects[i], rects[i + 1], rects[i + 2], rects[i + 3]);
    }
    ext_background_effect_surface_v1_set_blur_region (effect, region);
    if (region != NULL)
        wl_region_destroy (region);
}
