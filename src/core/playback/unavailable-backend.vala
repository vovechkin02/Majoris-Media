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

        /** Metadata signal; never emitted when the backend is unavailable. */
        public signal void metadata_changed ();

        /** Buffering signal; never emitted when the backend is unavailable. */
        public signal void buffering_changed (bool active, int percent);

        /** Seeking signal; never emitted when the backend is unavailable. */
        public signal void seeking_changed (bool active);

        /** Chapter signal; never emitted when the backend is unavailable. */
        public signal void chapter_changed (int index);

        /** Subtitle visibility signal; never emitted by an unavailable engine. */
        public signal void subtitle_visibility_changed (bool visible);

        /** Asynchronous command failure signal for an operational engine. */
        public signal void operation_failed (string message);

        /** No decoder is available to observe in this backend. */
        public signal void video_decoder_changed (string decoder);

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

        /** Cannot inspect source tracks without a running playback backend. */
        public Variant get_tracks () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Cannot inspect chapters without a running playback backend. */
        public Variant get_chapters () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses stream selection without a loaded media source. */
        public void select_track (TrackKind kind, string? id) throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses chapter navigation without a loaded media source. */
        public void select_chapter (uint index) throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses subtitle visibility changes without a playback engine. */
        public void set_subtitles_visible (bool visible) throws Error {
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
