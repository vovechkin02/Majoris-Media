namespace MediaKit {
    /** Interchangeable playback Strategy isolating engine specifics from MediaSession. */
    internal interface PlaybackBackend : Object {
        /** Whether backend engine support is compiled in. */
        public abstract bool is_available { get; }

        /** Natural end-of-stream event, excluding an explicit stop request. */
        public signal void ended ();

        /** A runtime backend failure delivered on the owning main context. */
        public signal void failed (string message);

        /** Actual pause-state notification from the engine. */
        public signal void pause_changed (bool paused);

        /** Position event in microseconds, never seconds. */
        public signal void position_changed (int64 position_us);

        /** Duration event in microseconds, or zero for unknown. */
        public signal void duration_changed (int64 duration_us);

        /** Resolves only on successful loaded-stream confirmation. */
        public abstract async void open_async (MediaSource source,
                                               Cancellable? cancellable = null) throws Error;

        /** Resumes the selected source. */
        public abstract void play () throws Error;

        /** Pauses the selected source. */
        public abstract void pause () throws Error;

        /** Stops decoding but retains the selected source. */
        public abstract void stop () throws Error;

        /** Seeks to a nonnegative microsecond position. */
        public abstract void seek (int64 position_us) throws Error;

        /** Creates one context-bound GL rendering endpoint when supported. */
        public abstract OpenGlOutput create_opengl_output () throws Error;

        /** Invalidates the backend and any pending source load. */
        public abstract void close ();
    }

    /** Native capability detection for builds with or without libmpv. */
    [CCode (cname = "mediakit_engine_is_available", cheader_filename = "engine-adapter.h")]
    internal extern static bool native_engine_is_available ();

    /** Native diagnostic for builds without a libmpv playback engine. */
    [CCode (cname = "mediakit_engine_unavailable_reason", cheader_filename = "engine-adapter.h")]
    internal extern static unowned string native_engine_unavailable_reason ();
}
