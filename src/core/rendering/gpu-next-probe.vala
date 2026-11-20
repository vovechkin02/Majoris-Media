[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Performs asynchronous, non-GTK preflight for standalone mpv 0.42+ gpu-next. */
    public sealed class GpuNextProbe : Object {
        /** Resolves mpv from PATH and checks the reported version without blocking GTK. */
        public async GpuNextCapabilities probe_async (
            Cancellable? cancellable = null
        ) throws Error {
            cancellable?.set_error_if_cancelled ();
            var executable = Environment.find_program_in_path ("mpv");
            if (executable == null) {
                return new GpuNextCapabilities ();
            }
            var wayland_display = Environment.get_variable ("WAYLAND_DISPLAY");
            bool wayland = wayland_display != null && wayland_display.length > 0;
            var launcher = new SubprocessLauncher (
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE
            );
            var process = launcher.spawn (executable, "--version");
            launcher.close ();
            string? stdout_data = null;
            string? stderr_data = null;
            bool timed_out = false;
            uint timeout_id = 0;
            timeout_id = Timeout.add_seconds (5, () => {
                timeout_id = 0;
                timed_out = true;
                process.force_exit ();
                return Source.REMOVE;
            });
            try {
                yield process.communicate_utf8_async (
                    null, cancellable, out stdout_data, out stderr_data
                );
            } catch (Error error) {
                process.force_exit ();
                if (timed_out) {
                    throw new MediaError.ENGINE_UNAVAILABLE (
                        "mpv version preflight exceeded its five-second deadline"
                    );
                }
                throw error;
            } finally {
                if (timeout_id != 0) {
                    Source.remove (timeout_id);
                }
            }
            if (timed_out) {
                throw new MediaError.ENGINE_UNAVAILABLE (
                    "mpv version preflight exceeded its five-second deadline"
                );
            }
            if (!process.get_successful ()) {
                throw new MediaError.ENGINE_UNAVAILABLE (
                    "Installed mpv did not return a usable version"
                );
            }
            return new GpuNextCapabilities.from_probe (
                executable, stdout_data ?? "", wayland
            );
        }
    }
}
