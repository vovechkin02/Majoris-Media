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

        /** Stream metadata or selection changed in libmpv. */
        public signal void metadata_changed ();

        /** Cache underrun pause and percent, distinct from user pause. */
        public signal void buffering_changed (bool active, int percent);

        /** Engine seek or resynchronization notification. */
        public signal void seeking_changed (bool active);

        /** Engine-selected chapter index, -1 if not applicable. */
        public signal void chapter_changed (int index);

        /** Engine-observed subtitle display state. */
        public signal void subtitle_visibility_changed (bool visible);

        /** An asynchronous stream/visibility command was rejected. */
        public signal void operation_failed (string message);

        /** Active decoder observed directly from libmpv, not the requested policy. */
        public signal void video_decoder_changed (string decoder);

        /** Native engine lifetime belongs exclusively to this backend. */
        private MediaKitNative.Engine engine;

        /** Native signal subscriptions are disconnected before backend disposal. */
        private ulong[] handlers = {};

        /** Marks a backend retired by a subsequent open or close. */
        private bool closed = false;

        /** Creates a per-request native engine to isolate superseded load completions. */
        public MpvBackend () {
            engine = new MediaKitNative.Engine ();
            weak MpvBackend weak_self = this;
            handlers += engine.ended.connect (() => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.ended ();
                }
            });
            handlers += engine.failed.connect ((message) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.failed (message);
                }
            });
            handlers += engine.pause_changed.connect ((paused) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.pause_changed (paused);
                }
            });
            handlers += engine.position_changed.connect ((position_us) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.position_changed (position_us);
                }
            });
            handlers += engine.duration_changed.connect ((duration_us) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.duration_changed (duration_us);
                }
            });
            handlers += engine.metadata_changed.connect (() => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.metadata_changed ();
                }
            });
            handlers += engine.buffering_changed.connect ((active, percent) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.buffering_changed (active, percent);
                }
            });
            handlers += engine.seeking_changed.connect ((active) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.seeking_changed (active);
                }
            });
            handlers += engine.chapter_changed.connect ((index) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.chapter_changed (index);
                }
            });
            handlers += engine.subtitle_visibility_changed.connect ((visible) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.subtitle_visibility_changed (visible);
                }
            });
            handlers += engine.operation_failed.connect ((message) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.operation_failed (message);
                }
            });
            handlers += engine.video_decoder_changed.connect ((decoder) => {
                if (weak_self != null && !weak_self.closed) {
                    weak_self.video_decoder_changed (decoder);
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

        /** Copies no frames: obtains a native metadata-only track snapshot. */
        public Variant get_tracks () throws Error {
            ensure_open ();
            return engine.get_tracks ();
        }

        /** Obtains the ordered chapter metadata from the native adapter. */
        public Variant get_chapters () throws Error {
            ensure_open ();
            return engine.get_chapters ();
        }

        /** Requests a validated stream change without blocking the GTK main loop. */
        public void select_track (TrackKind kind, string? id) throws Error {
            ensure_open ();
            string type_name;
            switch (kind) {
            case TrackKind.VIDEO:
                type_name = "video";
                break;
            case TrackKind.AUDIO:
                type_name = "audio";
                break;
            case TrackKind.SUBTITLE:
                type_name = "subtitle";
                break;
            default:
                throw new MediaError.INVALID_ARGUMENT ("Unknown stream type");
            }
            engine.select_track (type_name, id);
        }

        /** Queues chapter selection by index; the engine confirms the new chapter. */
        public void select_chapter (uint index) throws Error {
            ensure_open ();
            engine.select_chapter (index);
        }

        /** Queues subtitle display visibility without replacing the selected track. */
        public void set_subtitles_visible (bool visible) throws Error {
            ensure_open ();
            engine.set_subtitles_visible (visible);
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
