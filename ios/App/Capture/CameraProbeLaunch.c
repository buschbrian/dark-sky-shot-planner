// Debug launch hook for the capture tools (-CameraProbe YES), installed
// before main so DarkSkyApp.swift needs no change. The Swift hook checks its
// launch argument and returns at once when it is absent.
#if DEBUG
extern void ds_camera_probe_install(void);

__attribute__((constructor)) static void ds_capture_debug_hooks(void) {
    ds_camera_probe_install();
}
#endif
