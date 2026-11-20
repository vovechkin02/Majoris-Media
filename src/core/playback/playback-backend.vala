namespace MediaKit {
    /** Contract isolating playback operations from the public MediaSession API. */
    internal interface PlaybackBackend : Object {
        /** Indicates that this backend has been verified operational. */
        public abstract bool is_available { get; }

        /** Opens a source asynchronously, reporting errors without fake success. */
        public abstract async void open_async (MediaSource source,
                                               Cancellable? cancellable = null) throws Error;

        /** Starts playback only when this backend has a ready stream. */
        public abstract void play () throws Error;

        /** Pauses an operational stream without invalidating its metadata. */
        public abstract void pause () throws Error;

        /** Stops an operational stream while retaining the selected source. */
        public abstract void stop () throws Error;

        /** Seeks to a zero-based position in microseconds when supported. */
        public abstract void seek (int64 position_us) throws Error;

        /** Releases backend resources and clears any pending source. */
        public abstract void close ();
    }

    /** Private native bridge reports availability without exposing C implementation types. */
    [CCode (cname = "mediakit_engine_is_available", cheader_filename = "engine-adapter.h")]
    internal extern static bool native_engine_is_available ();

    /** Private native bridge provides the reason for an unavailable engine. */
    [CCode (cname = "mediakit_engine_unavailable_reason", cheader_filename = "engine-adapter.h")]
    internal extern static unowned string native_engine_unavailable_reason ();
}
