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

        /** Stream metadata or actual track selection changed. */
        public signal void metadata_changed ();

        /** Pause caused by cache starvation, with percent or -1 when unavailable. */
        public signal void buffering_changed (bool active, int percent);

        /** Active seek or playback resynchronization changed. */
        public signal void seeking_changed (bool active);

        /** Current chapter changed; -1 when no chapter is active. */
        public signal void chapter_changed (int index);

        /** Actual native subtitle visibility changed. */
        public signal void subtitle_visibility_changed (bool visible);

        /** An accepted control command failed asynchronously without ending playback. */
        public signal void operation_failed (string message);

        /** Actual active video decoder changes, `no` meaning software fallback. */
        public signal void video_decoder_changed (string decoder);

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

        /** Returns structured live tracks as aa{sv}, not application UI strings. */
        public abstract Variant get_tracks () throws Error;

        /** Returns ordered chapter markers as aa{sv}. */
        public abstract Variant get_chapters () throws Error;

        /** Queues a video/audio/subtitle stream change; null disables its stream. */
        public abstract void select_track (TrackKind kind, string? id) throws Error;

        /** Navigates to one zero-based chapter index. */
        public abstract void select_chapter (uint index) throws Error;

        /** Controls subtitle visibility independently of selected subtitle track. */
        public abstract void set_subtitles_visible (bool visible) throws Error;

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
