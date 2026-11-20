namespace MediaKit {
    /** Explicit unsupported backend for intentionally libmpv-disabled builds. */
    internal sealed class UnavailableBackend : Object, PlaybackBackend {
        /** Reports no usable playback engine in this build. */
        public bool is_available {
            get {
                return false;
            }
        }

        /** Natural termination signal; never emitted by an unavailable engine. */
        public signal void ended ();

        /** Runtime error signal; load operations throw directly instead. */
        public signal void failed (string message);

        /** Pause-state signal; never emitted by an unavailable engine. */
        public signal void pause_changed (bool paused);

        /** Position signal; never emitted by an unavailable engine. */
        public signal void position_changed (int64 position_us);

        /** Duration signal; never emitted by an unavailable engine. */
        public signal void duration_changed (int64 duration_us);

        /** Reports missing engine without inventing a successful file load. */
        public async void open_async (MediaSource source,
                                      Cancellable? cancellable = null) throws Error {
            cancellable?.set_error_if_cancelled ();
            Idle.add (open_async.callback);
            yield;
            cancellable?.set_error_if_cancelled ();
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses playback without an operational native engine. */
        public void play () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses pause without an operational native engine. */
        public void pause () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses stop without an operational native engine. */
        public void stop () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses seek without an operational native engine. */
        public void seek (int64 position_us) throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses GL renderer creation without an operational native engine. */
        public OpenGlOutput create_opengl_output () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** No native resources exist in this backend. */
        public void close () {
        }
    }
}
