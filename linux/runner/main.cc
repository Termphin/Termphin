#include <stdlib.h>
#include <unistd.h>

#include "my_application.h"

/// Points EGL at Mesa when the proprietary NVIDIA driver is loaded.
///
/// Through NVIDIA's EGL, Flutter's frames reach the window misplaced - the
/// app shows in a corner of a black window while input still lands where it
/// should - on Wayland and XWayland alike. Mesa draws on an integrated GPU
/// when there is one and falls back to software otherwise, both correct. A
/// vendor the user chose themselves is left alone.
static void prefer_mesa_over_nvidia_egl() {
  if (getenv("__EGL_VENDOR_LIBRARY_FILENAMES") != nullptr) return;
  if (access("/proc/driver/nvidia", F_OK) != 0) return;
  static const char* const kMesaVendors[] = {
      "/usr/share/glvnd/egl_vendor.d/50_mesa.json",
      "/etc/glvnd/egl_vendor.d/50_mesa.json",
  };
  for (const char* vendor : kMesaVendors) {
    if (access(vendor, R_OK) == 0) {
      setenv("__EGL_VENDOR_LIBRARY_FILENAMES", vendor, 0);
      return;
    }
  }
}

int main(int argc, char** argv) {
  prefer_mesa_over_nvidia_egl();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
