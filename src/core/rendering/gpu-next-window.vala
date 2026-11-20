[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Owns a distinct Wayland mpv gpu-next process and a private local IPC channel. */
    public sealed class GpuNextWindow : Object {
        /** True while an external playback process remains owned by this object. */
        public bool running { get; private set; default = false; }

        /** True after the subprocess has accepted an authenticated local IPC request. */
        public bool ready { get; private set; default = false; }

        /** Fired once when a process exits while this owner is still active. */
        public signal void finished (bool successful, int exit_status);

        /** Process owned exclusively by this instance. */
        private Subprocess? process;

        /** Single process-control transport, never exposed outside the process owner. */
        private GpuNextIpc? ipc;

        /** Private temporary directory containing the socket. */
        private string? ipc_directory;

        /** Absolute private socket pathname. */
        private string? ipc_socket;

        /** True when the owner has permanently relinquished its process. */
        private bool closed = false;

        /** Blocks concurrent launches before asynchronous preflight finishes. */
        private bool opening = false;

        /** Cancelable preflight and startup probe. */
        private Cancellable? pending_probe;

        /** Ignores stale subprocess completion callbacks after closure. */
        private uint64 generation = 0;

        /** Creates an idle standalone renderer without creating an mpv instance. */
        public GpuNextWindow () {
            Object ();
        }

        /** Opens a dedicated gpu-next Wayland window and waits for live control readiness. */
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
                        "A Wayland session and mpv 0.42+ are required for gpu-next"
                    );
                }
                var arguments = configuration.build_arguments (capabilities.executable, source);
                request.set_error_if_cancelled ();
                ipc_directory = DirUtils.make_tmp ("majoris-media-gpu-next-XXXXXX");
                ipc_socket = Path.build_filename (ipc_directory, "control.sock");
                if (ipc_socket.length > 100) {
                    throw new MediaError.UNSUPPORTED (
                        "Private IPC socket path exceeds the supported Unix-domain length"
                    );
                }
                ipc = new GpuNextIpc (ipc_socket);
                string[] launch_arguments = {};
                foreach (var argument in arguments) {
                    // The IPC option must precede '--' and the media pathname.
                    if (argument == "--") {
                        launch_arguments += "--input-ipc-server=" + ipc_socket;
                    }
                    launch_arguments += argument;
                }
                var launcher = new SubprocessLauncher (
                    SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE
                );
                var child = launcher.spawnv (launch_arguments);
                launcher.close ();
                process = child;
                running = true;
                uint64 token = ++generation;
                weak GpuNextWindow weak_self = this;
                child.wait_async.begin (null, (obj, result) => {
                    try {
                        child.wait_async.end (result);
                    } catch (Error error) {
                        warning ("Advanced renderer wait failed: %s", error.message);
                    }
                    if (weak_self != null && weak_self.generation == token) {
                        weak_self.complete (child);
                    }
                });
                yield wait_until_ready_async (request);
            } catch (Error error) {
                if (!closed) {
                    stop_child ();
                    clear_ipc ();
                    running = false;
                    ready = false;
                }
                throw error;
            } finally {
                if (cancellable != null && cancel_handler_id != 0) {
                    SignalHandler.disconnect (cancellable, cancel_handler_id);
                }
                if (pending_probe == request) {
                    pending_probe = null;
                }
                opening = false;
            }
        }

        /** Sets remote playback pause state without toggling an unknown current state. */
        public async void set_paused_async (bool paused, Cancellable? cancellable = null)
                                            throws Error {
            var transport = require_ipc ();
            yield transport.request_async (
                "set_property", "pause", null, null, paused, cancellable
            );
        }

        /** Seeks to a nonnegative absolute position, expressed in microseconds. */
        public async void seek_async (int64 position_us, Cancellable? cancellable = null)
                                      throws Error {
            if (position_us < 0) {
                throw new MediaError.INVALID_ARGUMENT ("Seek target must be nonnegative");
            }
            var transport = require_ipc ();
            double seconds = (double) position_us / 1000000.0;
            yield transport.request_async (
                "seek", null, seconds, "absolute+exact", null, cancellable
            );
        }

        /** Retrieves engine-side facts without claiming that a native HDR signal exists. */
        public async GpuNextPlaybackStatus query_status_async (
            Cancellable? cancellable = null
        ) throws Error {
            var transport = require_ipc ();
            var pause_node = yield transport.request_async (
                "get_property", "pause", null, null, null, cancellable
            );
            bool paused = pause_node.get_node_type () == Json.NodeType.VALUE &&
                pause_node.get_boolean ();
            int64 position_us = -1;
            string vo = "";
            string primaries = "";
            string transfer = "";
            string output_primaries = "";
            string output_transfer = "";
            try {
                var position_node = yield transport.request_async (
                    "get_property", "time-pos", null, null, null, cancellable
                );
                if (position_node.get_node_type () == Json.NodeType.VALUE) {
                    position_us = (int64) (position_node.get_double () * 1000000.0);
                }
            } catch (IOError.CANCELLED error) {
                throw error;
            } catch (Error error) {
                // A paused or opening stream may not yet have a position.
            }
            try {
                var vo_node = yield transport.request_async (
                    "get_property", "current-vo", null, null, null, cancellable
                );
                if (vo_node.get_node_type () == Json.NodeType.VALUE) {
                    vo = vo_node.get_string ();
                }
            } catch (IOError.CANCELLED error) {
                throw error;
            } catch (Error error) {
                // The VO property is not available on all mpv releases.
            }
            try {
                var params_node = yield transport.request_async (
                    "get_property", "video-params", null, null, null, cancellable
                );
                if (params_node.get_node_type () == Json.NodeType.OBJECT) {
                    var params = params_node.get_object ();
                    if (params.has_member ("primaries")) {
                        primaries = params.get_string_member ("primaries");
                    }
                    if (params.has_member ("gamma")) {
                        transfer = params.get_string_member ("gamma");
                    }
                }
            } catch (IOError.CANCELLED error) {
                throw error;
            } catch (Error error) {
                // Source metadata can legitimately be absent for audio-only streams.
            }
            try {
                // video-out-params describes mpv's rendered image, not actual
                // Wayland protocol negotiation or the display's active EOTF.
                var output_node = yield transport.request_async (
                    "get_property", "video-out-params", null, null, null, cancellable
                );
                if (output_node.get_node_type () == Json.NodeType.OBJECT) {
                    var output_params = output_node.get_object ();
                    if (output_params.has_member ("primaries")) {
                        output_primaries = output_params.get_string_member ("primaries");
                    }
                    if (output_params.has_member ("gamma")) {
                        output_transfer = output_params.get_string_member ("gamma");
                    }
                }
            } catch (IOError.CANCELLED error) {
                throw error;
            } catch (Error error) {
                // Some mpv versions/stream types have no post-processing snapshot.
            }
            return new GpuNextPlaybackStatus.with_output (
                paused, position_us, vo, primaries, transfer,
                output_primaries, output_transfer
            );
        }

        /** Requests orderly process exit without abandoning the owned process. */
        public void stop () {
            stop_child ();
        }

        /** Permanently cancels startup, kills the owned child, and releases private IPC. */
        public void close () {
            closed = true;
            pending_probe?.cancel ();
            generation++;
            if (process != null && running) {
                process.force_exit ();
            }
            process = null;
            running = false;
            ready = false;
            clear_ipc ();
        }

        /** Rejects commands before the mpv IPC endpoint has completed startup. */
        private GpuNextIpc require_ipc () throws Error {
            if (!running || !ready || closed || ipc == null) {
                throw new MediaError.INVALID_ARGUMENT (
                    "Advanced renderer must be running and ready before remote commands"
                );
            }
            return ipc;
        }

        /** Polls a private socket without blocking GTK or relying on arbitrary sleeps. */
        private async void wait_until_ready_async (Cancellable request) throws Error {
            for (int attempt = 0; attempt < 100; attempt++) {
                request.set_error_if_cancelled ();
                if (!running || closed) {
                    throw new MediaError.PLAYBACK_FAILED (
                        "Advanced player exited before establishing IPC"
                    );
                }
                if (ipc_socket != null &&
                    FileUtils.test (ipc_socket, FileTest.EXISTS) && ipc != null) {
                    try {
                        yield ipc.request_async (
                            "get_property", "pause", null, null, null, request
                        );
                        request.set_error_if_cancelled ();
                        ready = true;
                        return;
                    } catch (IOError.CANCELLED error) {
                        throw error;
                    } catch (Error error) {
                        // Socket creation may precede the server's listen operation.
                    }
                }
                yield delay_async (50);
            }
            throw new MediaError.ENGINE_UNAVAILABLE (
                "Advanced player IPC did not become available within five seconds"
            );
        }

        /** Schedules a cooperative delay on the owning GLib main context. */
        private async void delay_async (uint milliseconds) {
            SourceFunc continuation = delay_async.callback;
            Timeout.add (milliseconds, () => {
                continuation ();
                return Source.REMOVE;
            });
            yield;
        }

        /** Signals the process without waiting synchronously for the child. */
        private void stop_child () {
            if (process != null && running) {
                process.send_signal (15);
            }
        }

        /** Deletes only the socket and directory created by this instance. */
        private void clear_ipc () {
            ipc = null;
            if (ipc_socket != null) {
                FileUtils.remove (ipc_socket);
                ipc_socket = null;
            }
            if (ipc_directory != null) {
                DirUtils.remove (ipc_directory);
                ipc_directory = null;
            }
        }

        /** Publishes the child exit status once and releases private transport resources. */
        private void complete (Subprocess child) {
            bool successful = child.get_successful ();
            int status = child.get_if_exited () ? child.get_exit_status () : -1;
            process = null;
            running = false;
            ready = false;
            clear_ipc ();
            finished (successful, status);
        }

        /** Forces cleanup if a consuming application releases its process owner. */
        ~GpuNextWindow () {
            close ();
        }
    }
}
