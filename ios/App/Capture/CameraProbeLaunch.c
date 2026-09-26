// Debug launch hooks for the capture tools (-CameraProbe YES, -CaptureBench YES,
// -CaptureSelfTest YES), installed before main so DarkSkyApp.swift needs no
// change. Each Swift hook checks its launch argument and returns at once when
// it is absent.
#if DEBUG
extern void ds_camera_probe_install(void);
extern void ds_capture_bench_install(void);
extern void ds_capture_selftest_install(void);

__attribute__((constructor)) static void ds_capture_debug_hooks(void) {
    ds_camera_probe_install();
    ds_capture_bench_install();
    ds_capture_selftest_install();
}
#endif
