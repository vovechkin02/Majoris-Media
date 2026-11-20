namespace MediaKit {
    /** Explicit, non-playing backend used until the native decoder bridge is implemented. */
    internal sealed class UnavailableBackend : Object, PlaybackBackend {
        /** No operational playback engine is part of the Stage 1 delivery. */
        public bool is_available {
            get {
                return native_engine_is_available ();
            }
        }

        /** Yields once, then reports the absence of an operational backend. */
        public async void open_async (MediaSource source,
                                      Cancellable? cancellable = null) throws Error {
            cancellable?.set_error_if_cancelled ();
            Idle.add (open_async.callback);
            yield;
            cancellable?.set_error_if_cancelled ();
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses playback because no stream can be opened yet. */
        public void play () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses pause because no stream can be opened yet. */
        public void pause () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses stop because no stream can be opened yet. */
        public void stop () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses seek because no stream can be opened yet. */
        public void seek (int64 position_us) throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Does nothing because the unavailable adapter owns no media resources. */
        public void close () {
        }
    }
}
