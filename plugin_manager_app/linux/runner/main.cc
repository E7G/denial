#include "plugin_manager_application.h"
int main(int argc, char** argv) {
  // Keep Mesa off the framebuffer-fetch path that loses earlier backdrop layers.
  // Apply before GTK or Flutter creates a graphics context; preserve overrides.
  const gchar* extensions = g_getenv("MESA_EXTENSION_OVERRIDE");
  g_autofree gchar* safe_extensions = g_strconcat(
      extensions != nullptr ? extensions : "",
      " -GL_EXT_shader_framebuffer_fetch", nullptr);
  g_setenv("MESA_EXTENSION_OVERRIDE", safe_extensions, TRUE);
  g_autoptr(PluginManagerApplication) app = plugin_manager_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
