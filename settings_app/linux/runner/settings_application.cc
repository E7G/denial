#include "settings_application.h"

#include <cstring>
#include <initializer_list>

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _SettingsApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* activation_channel;
  gboolean welcome;
};

G_DEFINE_TYPE(SettingsApplication, settings_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(SettingsApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void clear_window_opaque_region(GtkWidget* widget, gpointer user_data) {
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window != nullptr) {
    // The Flutter view renders per-pixel alpha. GTK otherwise derives an
    // opaque region from the theme background and Wayland compositors may
    // legitimately skip effects intended for translucent surfaces. Reapply
    // this from style-updated because GTK can replace the region there.
    gdk_window_set_opaque_region(window, nullptr);
  }
}

static gboolean clear_window_background(GtkWidget*, cairo_t* cr, gpointer) {
  // app-paintable suppresses GTK's background, and Flutter blends its alpha
  // over this target. Replace old pixels before drawing the new frame so an
  // opaque frame cannot survive a switch back to glass or a window resize.
  // Keep GTK's dirty-region clip and restore the child's drawing operator.
  cairo_save(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
  cairo_paint(cr);
  cairo_restore(cr);
  return FALSE;
}

static void settings_method_call_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  SettingsApplication* self = DENIAL_SETTINGS_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (self->welcome && strcmp(method, "closeWindow") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    // Respond before destroying the engine which owns this method channel.
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, [](gpointer data) -> gboolean {
      auto* app = DENIAL_SETTINGS_APPLICATION(data);
      if (app->window != nullptr) gtk_widget_destroy(GTK_WIDGET(app->window));
      return G_SOURCE_REMOVE;
    }, g_object_ref(self), g_object_unref);
  } else if (self->welcome && strcmp(method, "openUrl") == 0) {
    FlValue* argument = fl_method_call_get_args(method_call);
    const gchar* uri = argument != nullptr && fl_value_get_type(argument) == FL_VALUE_TYPE_STRING
        ? fl_value_get_string(argument) : nullptr;
    g_autoptr(GError) launch_error = nullptr;
    if (uri == nullptr || (!g_str_has_prefix(uri, "https://") && !g_str_has_prefix(uri, "http://"))) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("invalid-url", "Expected a web URL", nullptr));
    } else if (!g_app_info_launch_default_for_uri(uri, nullptr, &launch_error)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("open-url", launch_error->message, nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "pickProfileImage") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const auto label = [args](const char* key, const char* fallback) {
      FlValue* value = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(args, key) : nullptr;
      return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
          ? fl_value_get_string(value) : fallback;
    };
    GtkWidget* dialog = gtk_file_chooser_dialog_new(
        label("title", "Choose photo"), self->window, GTK_FILE_CHOOSER_ACTION_OPEN,
        label("cancel", "Cancel"), GTK_RESPONSE_CANCEL,
        label("choose", "Choose photo"), GTK_RESPONSE_ACCEPT, nullptr);
    gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
    gtk_file_chooser_set_local_only(GTK_FILE_CHOOSER(dialog), TRUE);
    GtkFileFilter* filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, "PNG, JPEG, WebP, GIF, BMP");
    for (const char* mime : {"image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp"}) {
      gtk_file_filter_add_mime_type(filter, mime);
    }
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), filter);
    g_autoptr(FlValue) result = nullptr;
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
      g_autofree gchar* filename = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
      if (filename != nullptr) result = fl_value_new_string(filename);
    }
    gtk_widget_destroy(dialog);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "pickCursorZip") == 0) {
    GtkWidget* dialog = gtk_file_chooser_dialog_new(
        "Import cursor ZIP", self->window, GTK_FILE_CHOOSER_ACTION_OPEN,
        "_Cancel", GTK_RESPONSE_CANCEL, "_Import", GTK_RESPONSE_ACCEPT,
        nullptr);
    gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
    GtkFileFilter* zip_filter = gtk_file_filter_new();
    gtk_file_filter_set_name(zip_filter, "Cursor ZIP archives");
    gtk_file_filter_add_mime_type(zip_filter, "application/zip");
    gtk_file_filter_add_pattern(zip_filter, "*.zip");
    gtk_file_filter_add_pattern(zip_filter, "*.ZIP");
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), zip_filter);

    g_autoptr(FlValue) result = nullptr;
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
      g_autofree gchar* filename =
          gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
      if (filename != nullptr) {
        result = fl_value_new_string(filename);
      }
    }
    gtk_widget_destroy(dialog);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to Settings method %s: %s", method,
              error->message);
  }
}

static void settings_application_activate(GApplication* application) {
  SettingsApplication* self = DENIAL_SETTINGS_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));
  gtk_window_set_title(window, self->welcome ? "Welcome to Denial" : "Denial Settings");
  gtk_window_set_default_size(window, 900, 620);
  gtk_widget_set_size_request(GTK_WIDGET(window), 520, 400);
  gtk_window_set_decorated(window, FALSE);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  g_signal_connect(window, "draw", G_CALLBACK(clear_window_background), nullptr);
  g_signal_connect(window, "style-updated",
                   G_CALLBACK(clear_window_opaque_region), nullptr);
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  const GdkRGBA background_color = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));
  clear_window_opaque_region(GTK_WIDGET(window), nullptr);
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->activation_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "denial/settings_activation", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->activation_channel, settings_method_call_cb, self, nullptr);
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static void open_page_action(GSimpleAction* action,
                             GVariant* parameter,
                             gpointer user_data) {
  SettingsApplication* self = DENIAL_SETTINGS_APPLICATION(user_data);
  const gchar* page = g_variant_get_string(parameter, nullptr);
  if (self->window == nullptr) {
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    self->dart_entrypoint_arguments = g_new0(gchar*, 2);
    self->dart_entrypoint_arguments[0] =
        g_strdup_printf("--page=%s", page);
    g_application_activate(G_APPLICATION(self));
    return;
  }
  gtk_window_present(self->window);
  if (self->activation_channel != nullptr) {
    g_autoptr(FlValue) value = fl_value_new_string(page);
    fl_method_channel_invoke_method(self->activation_channel, "openPage", value,
                                    nullptr, nullptr, nullptr);
  }
}

static gboolean settings_application_local_command_line(
    GApplication* application,
    gchar*** arguments,
    int* exit_status) {
  SettingsApplication* self = DENIAL_SETTINGS_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register Denial Settings: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }
  const gchar* page = nullptr;
  for (gchar** argument = *arguments + 1; *argument != nullptr; argument++) {
    if (g_str_has_prefix(*argument, "--page=")) {
      page = *argument + strlen("--page=");
      break;
    }
  }
  if (g_application_get_is_remote(application) && page != nullptr && *page != '\0') {
    g_action_group_activate_action(G_ACTION_GROUP(application), "open-page",
                                   g_variant_new_string(page));
  } else {
    g_application_activate(application);
  }
  *exit_status = 0;
  return TRUE;
}

static void settings_application_dispose(GObject* object) {
  SettingsApplication* self = DENIAL_SETTINGS_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->activation_channel);
  G_OBJECT_CLASS(settings_application_parent_class)->dispose(object);
}

static void settings_application_class_init(SettingsApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = settings_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      settings_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = settings_application_dispose;
}

static void settings_application_init(SettingsApplication* self) {
  const GActionEntry actions[] = {
      {"open-page", open_page_action, "s", nullptr, nullptr, {0, 0, 0}},
  };
  g_action_map_add_action_entries(G_ACTION_MAP(self), actions,
                                  G_N_ELEMENTS(actions), self);
}

SettingsApplication* settings_application_new(gboolean welcome) {
  const char* id = welcome ? "dev.denial.Welcome" : APPLICATION_ID;
  g_set_prgname(id);
  auto* app = DENIAL_SETTINGS_APPLICATION(g_object_new(
      settings_application_get_type(),
      "application-id",
      id,
      "flags",
      G_APPLICATION_DEFAULT_FLAGS,
      nullptr));
  app->welcome = welcome;
  return app;
}
