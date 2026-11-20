[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Owns a separately windowed Wayland mpv gpu-next process, not a GTK render target. */
    public sealed class GpuNextWindow : Object {
        /** True while an external playback process remains owned by this object. */
        public bool running { get; private set; default = false; }

        /** Fired when the external mpv process exits; success does not certify HDR. */
        public signal void finished (bool successful, int exit_status);

        /** Active process, or null before launch and after its termination. */
        private Subprocess? process;

        /** A close request is terminal; disposed players cannot resume opening. */
        private bool closed = false;

        /** Prevents concurrent opens before an asynchronous preflight has completed. */
        private bool opening = false;

        /** Independently cancelable preflight operation owned by this window. */
        private Cancellable? pending_probe;

        /** Guards stale asynchronous process-exit callbacks after replacement. */
        private uint64 generation = 0;

        /** Creates an idle externally windowed renderer session. */
        public GpuNextWindow () {
            Object ();
        }

        /** Launches a second, independent playback session with its own Wayland surface. */
        public async void open_async (MediaSource source,
                                      GpuNextLaunchOptions? options = null,
                                      Cancellable? cancellable = null) throws Error {
            cancellable?.set_error_if_cancelled ();
            if (closed || running || opening) {
                throw new MediaError.INVALID_ARGUMENT (
                    "The advanced renderer is closed, opening, or already running"
                );
            }
            opening = true;
            var request = new Cancellable ();
            pending_probe = request;
            ulong cancel_handler_id = 0;
            if (cancellable != null) {
                cancel_handler_id = cancellable.cancelled.connect (() => {
                    request.cancel ();
                });
                if (cancellable.is_cancelled ()) {
                    request.cancel ();
                }
            }
            try {
                var configuration = options ?? new GpuNextLaunchOptions ();
                var probe = new GpuNextProbe ();
                var capabilities = yield probe.probe_async (request);
                if (closed || request.is_cancelled ()) {
                    throw new IOError.CANCELLED ("Advanced renderer opening was canceled");
                }
                if (!capabilities.can_launch) {
                    throw new MediaError.UNSUPPORTED (
                        "Wayland and mpv 0.42+ are required for standalone gpu-next"
                    );
                }
                var arguments = configuration.build_arguments (capabilities.executable, source);
                request.set_error_if_cancelled ();
                var launcher = new SubprocessLauncher (
                    SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE
                );
                var child = launcher.spawnv (arguments);
                launcher.close ();
                process = child;
                running = true;
                uint64 token = ++generation;
                weak GpuNextWindow weak_self = this;
                child.wait_async.begin (null, (obj, result) => {
                    try {
                        child.wait_async.end (result);
                    } catch (Error error) {
                        warning ("Advanced renderer process wait failed: %s", error.message);
                    }
                    if (weak_self != null && weak_self.generation == token) {
                        weak_self.complete (child);
                    }
                });
            } finally {
                if (cancellable != null && cancel_handler_id != 0) {
                    SignalHandler.disconnect (cancellable, cancel_handler_id);
                }
                pending_probe = null;
                opening = false;
            }
        }

        /** Requests an orderly exit; clients receive the final status asynchronously. */
        public void stop () {
            if (process != null && running) {
                process.send_signal (15);
            }
        }

        /** Forcibly releases a still-running child when the host is being disposed. */
        public void close () {
            closed = true;
            pending_probe?.cancel ();
            generation++;
            if (process != null && running) {
                process.force_exit ();
            }
            process = null;
            running = false;
        }

        /** Publishes exit status for the current process only. */
        private void complete (Subprocess child) {
            bool successful = child.get_successful ();
            int status = child.get_if_exited () ? child.get_exit_status () : -1;
            process = null;
            running = false;
            finished (successful, status);
        }

        /** Ensures closing an owning application does not leave an orphaned process. */
        ~GpuNextWindow () {
            close ();
        }
    }
}
