#include "plugin_manager_application.h"
#include <flutter_linux/flutter_linux.h>
#include "flutter/generated_plugin_registrant.h"

struct _PluginManagerApplication {
  GtkApplication parent_instance;
  GtkWindow* window;
};
G_DEFINE_TYPE(PluginManagerApplication, plugin_manager_application, GTK_TYPE_APPLICATION)

static void first_frame(GtkWidget* window) { gtk_widget_show(window); }

static void clear_window_opaque_region(GtkWidget* widget, gpointer) {
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window != nullptr) {
    // Preserve the Flutter surface's alpha when GTK updates its style.
    gdk_window_set_opaque_region(window, nullptr);
  }
}

static gboolean clear_window_background(GtkWidget*, cairo_t* cr, gpointer) {
  // GTK skips the background of app-paintable windows. Clear the dirty region
  // before Flutter blends its frame, including after an opaque-to-glass toggle
  // or resize; otherwise old pixels can remain behind the translucent areas.
  cairo_save(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
  cairo_paint(cr);
  cairo_restore(cr);
  return FALSE;
}

static void activate(GApplication* application) {
  auto* self = DENIAL_PLUGIN_MANAGER_APPLICATION(application);
  if (self->window != nullptr) { gtk_window_present(self->window); return; }
  self->window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  g_object_add_weak_pointer(G_OBJECT(self->window), reinterpret_cast<gpointer*>(&self->window));
  gtk_window_set_title(self->window, "Denial Plugins");
  gtk_window_set_default_size(self->window, 980, 700);
  gtk_widget_set_size_request(GTK_WIDGET(self->window), 440, 360);
  gtk_widget_set_app_paintable(GTK_WIDGET(self->window), TRUE);
  g_signal_connect(self->window, "draw", G_CALLBACK(clear_window_background), nullptr);
  g_signal_connect(self->window, "style-updated",
                   G_CALLBACK(clear_window_opaque_region), nullptr);
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(self->window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(self->window), visual);
  }
  // GTK supplies client decorations; the compositor must not add a second bar.
  auto* header = gtk_header_bar_new();
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), TRUE);
  gtk_header_bar_set_title(GTK_HEADER_BAR(header), "Denial Plugins");
  gtk_window_set_titlebar(self->window, header);
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  auto* view = fl_view_new(project);
  const GdkRGBA background_color = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(self->window), GTK_WIDGET(view));
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame), self->window);
  // The window stays hidden until Flutter's first frame. Realize the view now
  // so its engine starts without waiting for a second activation to show it.
  gtk_widget_realize(GTK_WIDGET(view));
  clear_window_opaque_region(GTK_WIDGET(self->window), nullptr);
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}
static void plugin_manager_application_class_init(PluginManagerApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = activate;
}
static void plugin_manager_application_init(PluginManagerApplication*) {}
PluginManagerApplication* plugin_manager_application_new() {
  g_set_prgname(APPLICATION_ID);
  return DENIAL_PLUGIN_MANAGER_APPLICATION(g_object_new(plugin_manager_application_get_type(),
      "application-id", APPLICATION_ID, "flags", G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
