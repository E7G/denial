#include "settings_application.h"

#include <cstdlib>
#include <string>
#include <utility>
#include <vector>
#include <glib/gstdio.h>

extern char **environ;

namespace {

void InstallLegacyDenialEnvironmentAliases() {
  std::vector<std::pair<std::string, std::string>> aliases;
  for (char **entry = environ; entry != nullptr && *entry != nullptr; ++entry) {
    const std::string assignment(*entry);
    const size_t separator = assignment.find('=');
    if (separator == std::string::npos) {
      continue;
    }
    const std::string name = assignment.substr(0, separator);
    constexpr char kCanonicalPrefix[] = "DENIAL_";
    if (name.rfind(kCanonicalPrefix, 0) != 0) {
      continue;
    }
    aliases.emplace_back("DENIA_" + name.substr(sizeof(kCanonicalPrefix) - 1),
                         assignment.substr(separator + 1));
  }
  for (const auto &alias : aliases) {
    setenv(alias.first.c_str(), alias.second.c_str(), 1);
  }
}

} // namespace

int main(int argc, char **argv) {
  // Mesa's framebuffer-fetch path can lose the layers preceding the final
  // backdrop filter. Set this before GTK or Flutter creates a graphics context.
  const gchar* extensions = g_getenv("MESA_EXTENSION_OVERRIDE");
  g_autofree gchar* safe_extensions = g_strconcat(
      extensions != nullptr ? extensions : "",
      " -GL_EXT_shader_framebuffer_fetch", nullptr);
  g_setenv("MESA_EXTENSION_OVERRIDE", safe_extensions, TRUE);
  InstallLegacyDenialEnvironmentAliases();
  bool welcome = false;
  bool autostart = false;
  for (int i = 1; i < argc; ++i) {
    welcome |= std::string(argv[i]) == "--welcome";
    autostart |= std::string(argv[i]) == "--autostart";
  }
  // Skip before registering/activating the app: completed setup must neither
  // create a window nor focus an already-open manual Welcome instance.
  if (welcome && autostart) {
    const char* config = g_getenv("XDG_CONFIG_HOME");
    g_autofree gchar* config_fallback = g_build_filename(g_get_home_dir(), ".config", nullptr);
    g_autofree gchar* directory = g_build_filename(
        config != nullptr && g_path_is_absolute(config) ? config : config_fallback,
        "denial", nullptr);
    g_autofree gchar* marker = g_build_filename(directory, "welcome", nullptr);
    if (g_file_test(marker, G_FILE_TEST_IS_REGULAR)) return 0;

    // Preserve completion from the initial Welcome version, then migrate to
    // the simple config marker. A failed migration must not reopen completed
    // onboarding; retry the migration at the next session start instead.
    const char* state = g_getenv("XDG_STATE_HOME");
    g_autofree gchar* fallback = g_build_filename(g_get_home_dir(), ".local", "state", nullptr);
    g_autofree gchar* legacy_marker = g_build_filename(
        state != nullptr && g_path_is_absolute(state) ? state : fallback,
        "denial", "welcome-completed", nullptr);
    if (g_file_test(legacy_marker, G_FILE_TEST_IS_REGULAR)) {
      if (g_mkdir_with_parents(directory, 0700) == 0 &&
          g_file_set_contents(marker, "1\n", 2, nullptr)) {
        g_unlink(legacy_marker);
      }
      return 0;
    }
  }
  g_autoptr(SettingsApplication) app = settings_application_new(welcome);
  return g_application_run(G_APPLICATION(app), argc, argv);
}
