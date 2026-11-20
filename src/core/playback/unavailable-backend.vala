namespace MediaKit {
    /** Explicit unsupported backend for intentionally libmpv-disabled builds. */
    internal sealed class UnavailableBackend : Object, PlaybackBackend {
        /** Reports no usable playback engine in this build. */
        public bool is_available {
            get {
                return false;
            }
        }

        /** Refuses source/output audio metadata access without a backend. */
        public Variant get_audio_information () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses audio output enumeration without an engine. */
        public Variant get_audio_devices () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses audio route changes without an initialized engine. */
        public void select_audio_device (string id) throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses color metadata access without an operational engine. */
        public Variant get_video_color () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

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

        /** No disc title metadata exists without a loaded native engine. */
        public Variant get_disc_titles () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** No disc navigation can be observed without a native engine. */
        public Variant get_disc_status () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Disc title selection is unavailable in this build. */
        public void select_disc_title (uint index) throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Disc menu commands are unavailable in this build. */
        public void navigate_disc_menu (DiscMenuAction action) throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** Refuses GL renderer creation without an operational native engine. */
        public OpenGlOutput create_opengl_output () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** The missing native engine cannot create an experimental GL endpoint. */
        public OpenGlOutput create_experimental_gpu_next_output () throws Error {
            throw new MediaError.ENGINE_UNAVAILABLE (native_engine_unavailable_reason ());
        }

        /** No native resources exist in this backend. */
        public void close () {
        }
    }
}
