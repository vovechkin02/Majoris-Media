[CCode (gir_namespace = "MediaKit", gir_version = "1.0")]
namespace MediaKit {
    /** Manages one playback source and presents backend-independent lifecycle events. */
    public sealed class MediaSession : Object {
        /** Current state, updated only after an actual backend result. */
        public PlaybackState state { get; private set; default = PlaybackState.EMPTY; }

        /** Currently requested source; null after close or before first open. */
        public MediaSource? source { get; private set; }

        /** Latest non-cancellation failure message, or null if none. */
        public string? last_error { get; private set; }

        /** Conservative capability snapshot for the current runtime. */
        public MediaCapabilities capabilities { get; private set; }

        /** Intended playback policy; assignment does not imply runtime support. */
        public PlaybackOptions options { get; construct; }

        /** Emitted on actual state transitions on the session's owning main context. */
        public signal void state_changed (PlaybackState state);

        /** The playback engine is private and must not leak through the public API. */
        private PlaybackBackend backend;

        /** Prevents late asynchronous completion from overwriting a subsequent close/open. */
        private uint64 request_generation = 0;

        /** Creates an independent session with no operational engine in Stage 1. */
        public MediaSession (PlaybackOptions? options = null) {
            Object (options: options ?? new PlaybackOptions ());
            backend = new UnavailableBackend ();
            capabilities = new MediaCapabilities (
                backend.is_available ? CapabilityStatus.AVAILABLE : CapabilityStatus.UNAVAILABLE
            );
        }

        /** Opens a source; never reports READY when the engine is not implemented. */
        public async void open_async (MediaSource requested_source,
                                      Cancellable? cancellable = null) throws Error {
            cancellable?.set_error_if_cancelled ();
            uint64 generation = ++request_generation;
            backend.close ();
            source = requested_source;
            last_error = null;
            update_state (PlaybackState.OPENING);

            try {
                yield backend.open_async (requested_source, cancellable);
                if (generation != request_generation) {
                    throw new IOError.CANCELLED ("Source open was superseded");
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
            }
        }

        /** Requests playback; errors rather than transitioning on unavailable engines. */
        public void play () throws Error {
            backend.play ();
            update_state (PlaybackState.PLAYING);
        }

        /** Requests pause; errors rather than transitioning on unavailable engines. */
        public void pause () throws Error {
            backend.pause ();
            update_state (PlaybackState.PAUSED);
        }

        /** Requests stop; errors rather than transitioning on unavailable engines. */
        public void stop () throws Error {
            backend.stop ();
            update_state (PlaybackState.STOPPED);
        }

        /** Requests a microsecond seek; negative positions are invalid. */
        public void seek (int64 position_us) throws Error {
            if (position_us < 0) {
                throw new MediaError.INVALID_ARGUMENT ("Seek position must not be negative");
            }
            backend.seek (position_us);
        }

        /** Invalidates pending operations and clears the session to EMPTY. */
        public void close () {
            request_generation++;
            backend.close ();
            source = null;
            last_error = null;
            update_state (PlaybackState.EMPTY);
        }

        /** Emits a single event for each real state change. */
        private void update_state (PlaybackState next_state) {
            if (state != next_state) {
                state = next_state;
                state_changed (next_state);
            }
        }
    }
}
