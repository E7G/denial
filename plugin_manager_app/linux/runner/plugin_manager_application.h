#ifndef DENIAL_PLUGIN_MANAGER_APPLICATION_H_
#define DENIAL_PLUGIN_MANAGER_APPLICATION_H_
#include <gtk/gtk.h>
G_DECLARE_FINAL_TYPE(PluginManagerApplication, plugin_manager_application, DENIAL,
                     PLUGIN_MANAGER_APPLICATION, GtkApplication)
PluginManagerApplication* plugin_manager_application_new();
#endif
