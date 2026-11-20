[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Playback Facade for one media source and its asynchronously managed engine. */
    public sealed class MediaSession : Object {
        /** Current lifecycle state, updated when native operations succeed or fail. */
        public PlaybackState state { get; private set; default = PlaybackState.EMPTY; }

        /** Current source, null before an open or after close. */
        public MediaSource? source { get; private set; }

        /** Latest playback failure; expected cancellations do not set this property. */
        public string? last_error { get; private set; }

        /** Runtime capability snapshot, conservative about untested display paths. */
        public MediaCapabilities capabilities { get; private set; }

        /** Caller-requested output policies, distinct from negotiated capabilities. */
        public PlaybackOptions options { get; construct; }

        /** Last observed playback position in microseconds. */
        public int64 position_us { get; private set; default = 0; }

        /** Last observed duration in microseconds, zero when unknown. */
        public int64 duration_us { get; private set; default = 0; }

        /** Emitted on each real state transition on the owning main context. */
        public signal void state_changed (PlaybackState state);

        /** Emitted before an old OpenGL endpoint must be released or a new one attached. */
        public signal void output_changed ();

        /** Emitted after observed playback position changes. */
        public signal void position_changed (int64 position_us);

        /** Emitted after observed stream duration changes. */
        public signal void duration_changed (int64 duration_us);

        /** Internal playback Strategy, never part of the installed public API. */
        private PlaybackBackend backend;

        /** Owns backend signal connection identifiers for deterministic disconnection. */
        private ulong[] backend_handlers = {};

        /** Unique request counter prevents superseded callbacks from mutating state. */
        private uint64 request_generation = 0;

        /** Retains current cancellable so close/open can cancel an in-flight request. */
        private Cancellable? current_load;

        /** Constructs a lightweight session without initializing libmpv at startup. */
        public MediaSession (PlaybackOptions? options = null) {
            Object (options: options ?? new PlaybackOptions ());
            backend = new UnavailableBackend ();
            attach_backend ();
            capabilities = new MediaCapabilities (
                native_engine_is_available ()
                    ? CapabilityStatus.AVAILABLE : CapabilityStatus.UNAVAILABLE
            );
        }

        /** Loads one validated source asynchronously, resolving after FILE_LOADED. */
        public async void open_async (MediaSource requested_source,
                                      Cancellable? cancellable = null) throws Error {
            cancellable?.set_error_if_cancelled ();
            uint64 generation = ++request_generation;
            cancel_pending ();
            detach_backend ();
            var old_backend = backend;
            backend = create_backend ();
            attach_backend ();
            source = requested_source;
            output_changed ();
            old_backend.close ();
            last_error = null;
            position_us = 0;
            duration_us = 0;
            position_changed (0);
            duration_changed (0);
            var request = new Cancellable ();
            current_load = request;
            ulong cancel_handler_id = 0;
            if (cancellable != null) {
                cancel_handler_id = cancellable.cancelled.connect (() => {
                    request.cancel ();
                });
                if (cancellable.is_cancelled ()) {
                    request.cancel ();
                }
            }
            update_state (PlaybackState.OPENING);

            try {
                yield backend.open_async (requested_source, request);
                if (request.is_cancelled () || generation != request_generation) {
                    throw new IOError.CANCELLED ("Media load was superseded");
                }
                update_state (PlaybackState.READY);
            } catch (Error error) {
                if (generation == request_generation) {
                    if (error is IOError.CANCELLED) {
                        source = null;
                        last_error = null;
                        update_state (PlaybackState.EMPTY);
                    } else {
                        last_error = error.message;
                        update_state (PlaybackState.ERROR);
                    }
                }
                throw error;
            } finally {
                if (cancellable != null && cancel_handler_id != 0) {
                    SignalHandler.disconnect (cancellable, cancel_handler_id);
                }
                if (generation == request_generation) {
                    current_load = null;
                }
            }
        }

        /** Resumes playback after a successful open, pause, stop or natural end. */
        public void play () throws Error {
            if (state != PlaybackState.READY && state != PlaybackState.PAUSED &&
                state != PlaybackState.STOPPED && state != PlaybackState.ENDED) {
                throw new MediaError.INVALID_ARGUMENT ("No ready stream to play");
            }
            if (state == PlaybackState.STOPPED || state == PlaybackState.ENDED) {
                backend.seek (0);
            }
            backend.play ();
            update_state (PlaybackState.PLAYING);
        }

        /** Pauses active playback only when a stream is playing. */
        public void pause () throws Error {
            if (state != PlaybackState.PLAYING) {
                throw new MediaError.INVALID_ARGUMENT ("Playback is not running");
            }
            backend.pause ();
            update_state (PlaybackState.PAUSED);
        }

        /** Stops an active or paused stream while retaining its source. */
        public void stop () throws Error {
            if (state != PlaybackState.PLAYING && state != PlaybackState.PAUSED &&
                state != PlaybackState.READY) {
                throw new MediaError.INVALID_ARGUMENT ("No active stream to stop");
            }
            backend.stop ();
            update_state (PlaybackState.STOPPED);
        }

        /** Seeks to a nonnegative microsecond position in the active stream. */
        public void seek (int64 position_us) throws Error {
            if (position_us < 0) {
                throw new MediaError.INVALID_ARGUMENT ("Seek position must not be negative");
            }
            if (state != PlaybackState.READY && state != PlaybackState.PLAYING &&
                state != PlaybackState.PAUSED && state != PlaybackState.ENDED) {
                throw new MediaError.INVALID_ARGUMENT ("No seekable stream is ready");
            }
            backend.seek (position_us);
        }

        /** Creates a GL output endpoint for an already initialized active backend. */
        public OpenGlOutput create_opengl_output () throws Error {
            return backend.create_opengl_output ();
        }

        /** Cancels pending work, detaches presentation and empties this session. */
        public void close () {
            ++request_generation;
            cancel_pending ();
            detach_backend ();
            var old_backend = backend;
            backend = new UnavailableBackend ();
            attach_backend ();
            source = null;
            output_changed ();
            old_backend.close ();
            last_error = null;
            position_us = 0;
            duration_us = 0;
            position_changed (0);
            duration_changed (0);
            update_state (PlaybackState.EMPTY);
        }

        /** Creates an operational backend only at the source-open boundary. */
        private static PlaybackBackend create_backend () {
            if (native_engine_is_available ()) {
                return new MpvBackend ();
            }
            return new UnavailableBackend ();
        }

        /** Subscribes to per-engine events and keeps GTK out of the playback core. */
        private void attach_backend () {
            backend_handlers += backend.ended.connect (() => {
                if (state == PlaybackState.PLAYING || state == PlaybackState.PAUSED) {
                    update_state (PlaybackState.ENDED);
                }
            });
            backend_handlers += backend.failed.connect ((message) => {
                if (state != PlaybackState.EMPTY) {
                    last_error = message;
                    update_state (PlaybackState.ERROR);
                }
            });
            backend_handlers += backend.pause_changed.connect ((paused) => {
                if (state == PlaybackState.PLAYING && paused) {
                    update_state (PlaybackState.PAUSED);
                } else if (state == PlaybackState.PAUSED && !paused) {
                    update_state (PlaybackState.PLAYING);
                }
            });
            backend_handlers += backend.position_changed.connect ((value) => {
                position_us = value;
                position_changed (value);
            });
            backend_handlers += backend.duration_changed.connect ((value) => {
                duration_us = value;
                duration_changed (value);
            });
        }

        /** Disconnects the old engine before its request is invalidated. */
        private void detach_backend () {
            foreach (var handler in backend_handlers) {
                SignalHandler.disconnect (backend, handler);
            }
            backend_handlers = {};
        }

        /** Cancels the superseded operation without canceling a caller-owned token. */
        private void cancel_pending () {
            current_load?.cancel ();
            current_load = null;
        }

        /** Emits one notification per effective lifecycle change. */
        private void update_state (PlaybackState next_state) {
            if (state != next_state) {
                state = next_state;
                state_changed (next_state);
            }
        }

        /** Completes source teardown and releases all engine signal subscriptions. */
        protected override void dispose () {
            cancel_pending ();
            output_changed ();
            detach_backend ();
            backend.close ();
            base.dispose ();
        }
    }
}
