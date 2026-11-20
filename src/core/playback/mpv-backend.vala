namespace MediaKit {
    /** Private libmpv Adapter implementing the neutral playback operation contract. */
    internal sealed class MpvBackend : Object, PlaybackBackend {
        /** Availability reflects compiled backend support, not device-level output support. */
        public bool is_available {
            get {
                return native_engine_is_available ();
            }
        }

        /** Notifies the session when playback naturally reaches end-of-file. */
        public signal void ended ();

        /** Notifies the session of a runtime decode or media error. */
        public signal void failed (string message);

        /** Observed pause state coming from the native engine. */
        public signal void pause_changed (bool paused);

        /** Observed stream position in microseconds. */
        public signal void position_changed (int64 position_us);

        /** Observed stream duration in microseconds. */
        public signal void duration_changed (int64 duration_us);

        /** Native engine lifetime belongs exclusively to this backend. */
        private MediaKitNative.Engine engine;

        /** Native signal subscriptions are disconnected before backend disposal. */
        private ulong[] handlers = {};

        /** Marks a backend retired by a subsequent open or close. */
        private bool closed = false;

        /** Creates a per-request native engine to isolate superseded load completions. */
        public MpvBackend () {
            engine = new MediaKitNative.Engine ();
            handlers += engine.ended.connect (() => {
                if (!closed) {
                    ended ();
                }
            });
            handlers += engine.failed.connect ((message) => {
                if (!closed) {
                    failed (message);
                }
            });
            handlers += engine.pause_changed.connect ((paused) => {
                if (!closed) {
                    pause_changed (paused);
                }
            });
            handlers += engine.position_changed.connect ((position_us) => {
                if (!closed) {
                    position_changed (position_us);
                }
            });
            handlers += engine.duration_changed.connect ((duration_us) => {
                if (!closed) {
                    duration_changed (duration_us);
                }
            });
        }

        /** Opens media asynchronously, resolving only after an actual libmpv load event. */
        public async void open_async (MediaSource source,
                                      Cancellable? cancellable = null) throws Error {
            cancellable?.set_error_if_cancelled ();
            if (closed) {
                throw new IOError.CANCELLED ("The playback backend was closed");
            }
            yield engine.load_async (source.uri, cancellable);
            if (closed) {
                throw new IOError.CANCELLED ("Media loading was superseded");
            }
        }

        /** Resumes the active playback stream. */
        public void play () throws Error {
            ensure_open ();
            engine.play ();
        }

        /** Pauses playback without unloading the source. */
        public void pause () throws Error {
            ensure_open ();
            engine.pause ();
        }

        /** Stops playback while retaining this backend object. */
        public void stop () throws Error {
            ensure_open ();
            engine.stop ();
        }

        /** Seeks in microseconds, preserving precision through the native adapter. */
        public void seek (int64 position_us) throws Error {
            ensure_open ();
            engine.seek (position_us);
        }

        /** Creates a GL renderer; the GTK owner must hold a current GL context. */
        public OpenGlOutput create_opengl_output () throws Error {
            ensure_open ();
            return new OpenGlOutput (engine.create_renderer ());
        }

        /** Invalidates callbacks and pending work before releasing native resources. */
        public void close () {
            if (closed) {
                return;
            }
            closed = true;
            foreach (var handler in handlers) {
                SignalHandler.disconnect (engine, handler);
            }
            handlers = {};
            engine.close ();
        }

        /** Fails operations deterministically after the backend has been retired. */
        private void ensure_open () throws Error {
            if (closed) {
                throw new MediaError.INVALID_ARGUMENT ("The playback backend is closed");
            }
        }

        /** Detaches native subscriptions even when the consumer forgot to close. */
        protected override void dispose () {
            close ();
            base.dispose ();
        }
    }
}
